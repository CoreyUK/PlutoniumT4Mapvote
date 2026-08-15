#include common_scripts\utility;
#include maps\_utility;
#include maps\_hud_util;

/*
    Plutonium T4 Zombies end-game map vote

    Stock flow:
      GAME OVER -> survived rounds -> 3 second presentation -> intermission

    The script extends zombie_intermission_time, starts the vote after the
    presentation, and prepares the winning map before stock ExitLevel().
*/

main()
{
    setDefaultDvar( "zmv_enable", "1" );
    if ( !getDvarInt( "zmv_enable" ) )
        return;

    setDefaultDvar( "zmv_time", "20" );
    setDefaultDvar( "zmv_result_time", "5" );
    setDefaultDvar( "zmv_delay", "4" );
    setDefaultDvar( "zmv_options", "3" );
    setDefaultDvar( "zmv_allow_current", "0" );
    setDefaultDvar( "zmv_maps", "nazi_zombie_prototype nazi_zombie_asylum nazi_zombie_sumpf nazi_zombie_factory" );
    setDefaultDvar( "zmv_debug", "0" );

    precacheZmLevelshots();

    level.zmv_running = false;
    level.zmv_finished = false;
    level.zmv_complete = false;
    level thread extendZombieIntermission();
    level thread watchForGameOver();

    if ( getDvarInt( "zmv_debug" ) )
        level thread debugVote();

    println( "[T4 ZM Map Vote v1.0] Loaded" );
    zmvLog( "loaded" );
}

extendZombieIntermission()
{
    while ( !isDefined( level.zombie_vars ) || !isDefined( level.zombie_vars["zombie_intermission_time"] ) )
        wait 0.05;

    delay = getDvarInt( "zmv_delay" );
    voteTime = getDvarInt( "zmv_time" );
    resultTime = getDvarInt( "zmv_result_time" );

    if ( delay < 3 )
        delay = 4;
    if ( voteTime < 5 )
        voteTime = 20;
    if ( resultTime < 2 )
        resultTime = 3;

    // Stock starts this timer three seconds after level.intermission becomes
    // true. The extra five seconds leave room for HUD creation and map exit.
    level.zombie_vars["zombie_intermission_time"] = delay + voteTime + resultTime + 5;
    println( "[T4 ZM Map Vote v1.0] Zombie intermission extended" );
    zmvLog( "intermission_extended" );
}

watchForGameOver()
{
    while ( !isDefined( level.intermission ) || !level.intermission )
        wait 0.05;

    if ( level.zmv_running )
        return;

    delay = getDvarInt( "zmv_delay" );
    if ( delay < 3 )
        delay = 4;

    println( "[T4 ZM Map Vote v1.0] Game over detected" );
    zmvLog( "game_over_detected" );
    wait delay;
    level startZmMapVote();
}

debugVote()
{
    wait 5;
    if ( !level.zmv_running )
        level thread startZmMapVote();
}

startZmMapVote()
{
    if ( level.zmv_running )
        return;

    level.zmv_running = true;
    level.zmv_finished = false;
    level.zmv_complete = false;
    level.zmv_options = buildZmMapOptions();

    if ( level.zmv_options.size < 3 )
    {
        println( "[T4 ZM Map Vote] zmv_maps needs at least two eligible maps." );
        zmvLog( "invalid_map_pool" );
        level.zmv_running = false;
        return;
    }

    level.zmv_votes = [];
    for ( i = 0; i < level.zmv_options.size; i++ )
        level.zmv_votes[i] = 0;

    players = get_players();
    for ( i = 0; i < players.size; i++ )
    {
        player = players[i];
        player.zmv_vote = -1;
        player.zmv_cursor = 0;
        player thread createZmVoteHud();
        player thread handleZmVoteInput();
    }

    timeLeft = getDvarInt( "zmv_time" );
    if ( timeLeft < 5 )
        timeLeft = 20;

    println( "[T4 ZM Map Vote v1.0] Vote started" );
    zmvLog( "vote_started" );

    while ( timeLeft > 0 && !level.zmv_finished )
    {
        level.zmv_time_left = timeLeft;
        level updateAllZmVoteHuds();
        wait 1;
        timeLeft--;
    }

    if ( level.zmv_finished )
        return;

    level.zmv_time_left = 0;
    level updateAllZmVoteHuds();
    winner = chooseZmWinner();
    level finishZmVote( winner );
}

buildZmMapOptions()
{
    pool = strTok( getDvar( "zmv_maps" ), " " );
    clean = [];
    current = getDvar( "mapname" );

    for ( i = 0; i < pool.size; i++ )
    {
        map = normalizeZmMapId( pool[i] );
        if ( map == "" )
            continue;
        if ( !getDvarInt( "zmv_allow_current" ) && map == current )
            continue;
        if ( arrayContainsZm( clean, map ) )
            continue;
        clean[clean.size] = map;
    }

    totalOptions = getDvarInt( "zmv_options" );
    if ( totalOptions < 3 )
        totalOptions = 3;
    if ( totalOptions > 5 )
        totalOptions = 5;

    namedCount = totalOptions - 1;
    if ( namedCount > clean.size )
        namedCount = clean.size;

    options = [];
    while ( options.size < namedCount )
    {
        index = randomInt( clean.size );
        options[options.size] = clean[index];
        clean = removeZmArrayIndex( clean, index );
    }

    level.zmv_random_pool = clean;
    options[options.size] = "__random__";
    return options;
}

createZmVoteHud()
{
    self endon( "disconnect" );
    level endon( "zmv_cleanup" );

    self.zmv_hud = [];

    background = newClientHudElem( self );
    background.horzAlign = "center";
    background.vertAlign = "middle";
    background.alignX = "center";
    background.alignY = "middle";
    background.x = 0;
    background.y = 0;
    background.sort = 201;
    background.foreground = true;
    background.alpha = 0.88;
    background.color = ( 0.02, 0.02, 0.025 );
    background setShader( "white", 640, 480 );
    self.zmv_hud[self.zmv_hud.size] = background;

    title = createFontString( "objective", 2.0 );
    title setPoint( "CENTER", "CENTER", 0, -125 );
    title.sort = 205;
    title.foreground = true;
    title.color = ( 0.92, 0.72, 0.20 );
    title setText( "VOTE FOR THE NEXT ZOMBIES MAP" );
    self.zmv_hud[self.zmv_hud.size] = title;

    self.zmv_cards = [];
    columns = 3;
    twoRows = level.zmv_options.size > 3;

    for ( i = 0; i < level.zmv_options.size; i++ )
    {
        row = int( i / columns );
        column = i % columns;
        x = -140 + ( column * 140 );
        if ( twoRows )
            y = -58 + ( row * 108 );
        else
            y = -10;

        card = spawnStruct();

        card.border = newClientHudElem( self );
        card.border.horzAlign = "center";
        card.border.vertAlign = "middle";
        card.border.alignX = "center";
        card.border.alignY = "middle";
        card.border.x = x;
        card.border.y = y;
        card.border.sort = 202;
        card.border.foreground = true;
        card.border.alpha = 0.7;
        card.border.color = ( 0.20, 0.20, 0.20 );
        card.border setShader( "white", 130, 98 );
        self.zmv_hud[self.zmv_hud.size] = card.border;

        card.image = newClientHudElem( self );
        card.image.horzAlign = "center";
        card.image.vertAlign = "middle";
        card.image.alignX = "center";
        card.image.alignY = "middle";
        card.image.x = x;
        card.image.y = y - 7;
        card.image.sort = 203;
        card.image.foreground = true;
        card.image.alpha = 1;

        if ( level.zmv_options[i] == "__random__" )
        {
            card.image.color = getZmCardColor( i );
            card.image setShader( "white", 124, 76 );
        }
        else
        {
            card.image.color = ( 1, 1, 1 );
            card.image setShader( getZmMapShader( level.zmv_options[i] ), 124, 76 );
        }
        self.zmv_hud[self.zmv_hud.size] = card.image;

        card.name = createFontString( "default", 1.25 );
        card.name setPoint( "CENTER", "CENTER", x, y + 40 );
        card.name.sort = 205;
        card.name.foreground = true;
        card.name setText( getZmMapName( level.zmv_options[i] ) );
        self.zmv_hud[self.zmv_hud.size] = card.name;

        card.votes = createFontString( "default", 1.15 );
        card.votes setPoint( "CENTER", "CENTER", x + 48, y + 40 );
        card.votes.sort = 206;
        card.votes.foreground = true;
        card.votes setValue( 0 );
        self.zmv_hud[self.zmv_hud.size] = card.votes;

        self.zmv_cards[i] = card;
    }

    self.zmv_timer = createFontString( "objective", 1.45 );
    if ( twoRows )
        self.zmv_timer setPoint( "CENTER", "CENTER", 0, 148 );
    else
        self.zmv_timer setPoint( "CENTER", "CENTER", 0, 100 );
    self.zmv_timer.sort = 205;
    self.zmv_timer.foreground = true;
    self.zmv_timer setText( "AIM: PREVIOUS   FIRE: NEXT   USE/RELOAD: VOTE" );
    self.zmv_hud[self.zmv_hud.size] = self.zmv_timer;

    self updateZmVoteHud();
}

handleZmVoteInput()
{
    self endon( "disconnect" );
    level endon( "zmv_cleanup" );

    wait 1;
    self notifyOnPlayerCommand( "zmv_prev", "+speed_throw" );
    self notifyOnPlayerCommand( "zmv_next", "+attack" );
    self notifyOnPlayerCommand( "zmv_use", "+activate" );
    self notifyOnPlayerCommand( "zmv_reload", "+reload" );

    for ( ;; )
    {
        command = self waittill_any_return( "zmv_prev", "zmv_next", "zmv_use", "zmv_reload" );

        if ( command == "zmv_prev" )
        {
            self.zmv_cursor--;
            if ( self.zmv_cursor < 0 )
                self.zmv_cursor = level.zmv_options.size - 1;
        }
        else if ( command == "zmv_next" )
        {
            self.zmv_cursor++;
            if ( self.zmv_cursor >= level.zmv_options.size )
                self.zmv_cursor = 0;
        }
        else
        {
            self castZmVote( self.zmv_cursor );
        }

        self updateZmVoteHud();
        wait 0.12;
    }
}

castZmVote( index )
{
    if ( index < 0 || index >= level.zmv_options.size )
        return;

    if ( self.zmv_vote >= 0 )
        level.zmv_votes[self.zmv_vote]--;

    self.zmv_vote = index;
    level.zmv_votes[index]++;
    level updateAllZmVoteHuds();
}

updateAllZmVoteHuds()
{
    players = get_players();
    for ( i = 0; i < players.size; i++ )
        if ( isDefined( players[i].zmv_hud ) )
            players[i] updateZmVoteHud();
}

updateZmVoteHud()
{
    if ( !isDefined( self.zmv_cards ) )
        return;

    for ( i = 0; i < self.zmv_cards.size; i++ )
    {
        if ( i == self.zmv_cursor )
        {
            self.zmv_cards[i].border.color = ( 0.25, 0.65, 1.0 );
            self.zmv_cards[i].border.alpha = 1;
        }
        else
        {
            self.zmv_cards[i].border.color = ( 0.20, 0.20, 0.20 );
            self.zmv_cards[i].border.alpha = 0.7;
        }

        if ( self.zmv_vote == i )
        {
            self.zmv_cards[i].name.color = ( 0.35, 1.0, 0.35 );
            self.zmv_cards[i].border.color = ( 0.20, 0.75, 0.30 );
        }
        else
        {
            self.zmv_cards[i].name.color = ( 1, 1, 1 );
        }

        self.zmv_cards[i].votes setValue( level.zmv_votes[i] );
    }

    if ( isDefined( self.zmv_timer ) && isDefined( level.zmv_time_left ) )
        self.zmv_timer setText( "AIM: PREVIOUS   FIRE: NEXT   USE/RELOAD: VOTE     TIME: " + level.zmv_time_left );
}

finishZmVote( winner )
{
    if ( level.zmv_finished )
        return;

    level.zmv_finished = true;

    players = get_players();
    for ( i = 0; i < players.size; i++ )
    {
        if ( isDefined( players[i].zmv_cards ) )
        {
            players[i].zmv_cards[winner].border.color = ( 0.95, 0.68, 0.12 );
            players[i].zmv_cards[winner].border.alpha = 1;
        }
    }

    chosenMap = level.zmv_options[winner];
    if ( chosenMap == "__random__" )
    {
        if ( level.zmv_random_pool.size > 0 )
            chosenMap = level.zmv_random_pool[randomInt( level.zmv_random_pool.size )];
        else
            chosenMap = level.zmv_options[randomInt( level.zmv_options.size - 1 )];
    }

    rotation = "map " + chosenMap;
    setDvar( "sv_mapRotationCurrent", rotation );
    setDvar( "sv_mapRotation", rotation );
    println( "[T4 ZM Map Vote] Winner: " + chosenMap );
    zmvLog( "winner_" + chosenMap );

    for ( i = 0; i < players.size; i++ )
    {
        if ( isDefined( players[i].zmv_timer ) )
        {
            players[i].zmv_timer.color = ( 0.35, 1.0, 0.35 );
            players[i].zmv_timer setText( "WINNER: " + getZmMapName( chosenMap ) );
        }
    }

    resultTime = getDvarInt( "zmv_result_time" );
    if ( resultTime < 2 )
        resultTime = 3;
    wait resultTime;

    level notify( "zmv_cleanup" );
    level cleanupZmVoteHuds();
    level.zmv_complete = true;
}

cleanupZmVoteHuds()
{
    players = get_players();
    for ( i = 0; i < players.size; i++ )
    {
        if ( !isDefined( players[i].zmv_hud ) )
            continue;

        for ( j = 0; j < players[i].zmv_hud.size; j++ )
            if ( isDefined( players[i].zmv_hud[j] ) )
                players[i].zmv_hud[j] destroy();

        players[i].zmv_hud = undefined;
    }
}

chooseZmWinner()
{
    best = -1;
    tied = [];

    for ( i = 0; i < level.zmv_votes.size; i++ )
    {
        if ( level.zmv_votes[i] > best )
        {
            best = level.zmv_votes[i];
            tied = [];
            tied[0] = i;
        }
        else if ( level.zmv_votes[i] == best )
        {
            tied[tied.size] = i;
        }
    }

    return tied[randomInt( tied.size )];
}

normalizeZmMapId( map )
{
    switch ( toLower( map ) )
    {
        case "nacht": return "nazi_zombie_prototype";
        case "verruckt": return "nazi_zombie_asylum";
        case "shi_no_numa": return "nazi_zombie_sumpf";
        case "der_riese": return "nazi_zombie_factory";
        default: return toLower( map );
    }
}

getZmMapName( map )
{
    switch ( map )
    {
        case "__random__": return "RANDOM";
        case "nazi_zombie_prototype": return "NACHT DER UNTOTEN";
        case "nazi_zombie_asylum": return "VERRUCKT";
        case "nazi_zombie_sumpf": return "SHI NO NUMA";
        case "nazi_zombie_factory": return "DER RIESE";
        default: return map;
    }
}

getZmMapShader( map )
{
    switch ( map )
    {
        case "nazi_zombie_prototype": return "zmv_loadscreen_nacht";
        case "nazi_zombie_asylum": return "zmv_loadscreen_verruckt";
        case "nazi_zombie_sumpf": return "zmv_loadscreen_shi_no_numa";
        case "nazi_zombie_factory": return "zmv_loadscreen_der_riese";
        default: return "white";
    }
}

precacheZmLevelshots()
{
    precacheShader( "white" );
    precacheShader( "zmv_loadscreen_nacht" );
    precacheShader( "zmv_loadscreen_verruckt" );
    precacheShader( "zmv_loadscreen_shi_no_numa" );
    precacheShader( "zmv_loadscreen_der_riese" );
}

getZmCardColor( index )
{
    switch ( index )
    {
        case 0: return ( 0.20, 0.27, 0.34 );
        case 1: return ( 0.28, 0.22, 0.18 );
        case 2: return ( 0.18, 0.30, 0.22 );
        case 3: return ( 0.30, 0.18, 0.18 );
        default: return ( 0.22, 0.20, 0.32 );
    }
}

setDefaultDvar( name, value )
{
    if ( getDvar( name ) == "" )
        setDvar( name, value );
}

arrayContainsZm( array, value )
{
    for ( i = 0; i < array.size; i++ )
        if ( array[i] == value )
            return true;
    return false;
}

removeZmArrayIndex( array, index )
{
    result = [];
    for ( i = 0; i < array.size; i++ )
        if ( i != index )
            result[result.size] = array[i];
    return result;
}

zmvLog( message )
{
    logPrint( "ZMV;" + message + "\n" );
}
