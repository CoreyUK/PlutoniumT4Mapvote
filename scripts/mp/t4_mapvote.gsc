#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\gametypes\_hud_util;

/*
    T4MP Map Vote for Plutonium

    Controls:
      Aim / left mouse equivalent  - previous map
      Fire / right trigger         - next map
      Use / reload                 - vote

    Stock loading-screen images are supplied by the t4_mapvote_assets mod.
*/

main()
{
    setDefaultDvar( "mv_enable", "1" );
    if ( !getDvarInt( "mv_enable" ) )
        return;

    setDefaultDvar( "mv_time", "20" );
    setDefaultDvar( "mv_result_time", "5" );
    setDefaultDvar( "mv_options", "3" );
    setDefaultDvar( "mv_allow_dlc", "1" );
    setDefaultDvar( "mv_maps", "mp_airfield mp_asylum mp_castle mp_courtyard mp_dome mp_downfall mp_hangar mp_makin mp_makin_day mp_outskirts mp_roundhouse mp_seelow mp_shrine mp_suburban mp_kneedeep mp_nachtfeuer mp_subway mp_docks mp_kwai mp_stalingrad mp_drum mp_bgate mp_vodka" );
    setDefaultDvar( "mv_gametypes", "" );
    setDefaultDvar( "mv_gametype_names", "" );
    setDefaultDvar( "mv_allow_current", "0" );
    setDefaultDvar( "mv_debug", "0" );

    precacheT4Levelshots();

    // PC dedicated servers use this value after the final scoreboard opens.
    setDvar( "scr_intermission_time", getDvarInt( "mv_time" ) + getDvarInt( "mv_result_time" ) + 3 );

    level.mv_running = false;
    level.mv_final_game = false;
    level thread watchForPlayers();
    level thread installFinalGameHook();

    if ( getDvarInt( "mv_debug" ) )
        level thread debugVote();

    println( "[T4 Map Vote v0.9] Loaded" );
    mvLog( "loaded" );
}

watchForPlayers()
{
    for ( ;; )
    {
        level waittill( "connected", player );
        player.mv_vote = -1;
        player.mv_cursor = 0;
    }
}

installFinalGameHook()
{
    level waittill( "prematch_over" );

    // T4 executes custom script main() again on round restart but can retain
    // level callback pointers. Never wrap our own hooks a second time: doing so
    // would call the original S&D scoring callback more than once.
    if ( isDefined( level.mv_hooks_installed ) && level.mv_hooks_installed )
    {
        println( "[T4 Map Vote v0.9] Final-game hooks already installed" );
        mvLog( "hooks_already_installed" );
        return;
    }

    level.mv_original_on_end_game = level.onEndGame;
    level.mv_original_on_round_end_game = level.onRoundEndGame;
    level.onEndGame = ::mapVoteSingleRoundCallback;
    level.onRoundEndGame = ::mapVoteFinalGameCallback;
    level.mv_hooks_installed = true;
    println( "[T4 Map Vote v0.9] Final-game hooks installed" );
    mvLog( "hooks_installed" );
}

mapVoteSingleRoundCallback( winner )
{
    if ( isDefined( level.mv_original_on_end_game ) )
        [[level.mv_original_on_end_game]]( winner );

    singleRoundGame = !( level.roundLimit > 1 || ( !level.roundLimit && level.scoreLimit != 1 ) );
    if ( singleRoundGame )
    {
        println( "[T4 Map Vote v0.9] Single-round final confirmed" );
        mvLog( "single_round_final_confirmed" );
        level.mv_final_game = true;
        setDvar( "scr_intermission_time", getDvarInt( "mv_time" ) + getDvarInt( "mv_result_time" ) + 5 );
        level thread queueFinalMapVote();
    }
}

mapVoteFinalGameCallback( winner )
{
    result = winner;
    if ( isDefined( level.mv_original_on_round_end_game ) )
        result = [[level.mv_original_on_round_end_game]]( winner );

    level.mv_final_game = true;
    setDvar( "scr_intermission_time", getDvarInt( "mv_time" ) + getDvarInt( "mv_result_time" ) + 5 );
    println( "[T4 Map Vote v0.9] Multi-round final confirmed" );
    mvLog( "multi_round_final_confirmed" );
    level thread queueFinalMapVote();
    return result;
}

queueFinalMapVote()
{
    if ( isDefined( level.mv_vote_queued ) && level.mv_vote_queued )
    {
        mvLog( "queue_rejected_already_queued" );
        return;
    }
    level.mv_vote_queued = true;
    mvLog( "queue_started_wait_12" );

    // Allow both the stock Victory/Defeat presentation and its subsequent EOG
    // scoreboard open call to complete before replacing that menu.
    wait 12;
    println( "[T4 Map Vote v0.9] Stock scoreboard opened; replacing with vote" );
    mvLog( "queue_wait_complete_starting_vote" );

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( isRealPlayer( players[i] ) )
        {
            // T4 automatically draws the scoreboard whenever the player remains
            // in its stock "intermission" session state.
            players[i].sessionstate = "spectator";
            players[i].spectatorclient = -1;
            players[i] closeMenu();
            players[i] closeInGameMenu();
        }
    }

    level startMapVote();
}

debugVote()
{
    wait 5;
    if ( !level.mv_running )
        level thread startMapVote();
}

startMapVote()
{
    if ( level.mv_running )
        return;

    println( "[T4 Map Vote] Starting vote" );
    mvLog( "start_vote_entered" );
    level.mv_running = true;
    level.mv_finished = false;
    level.mv_complete = false;
    level.mv_options = buildMapOptions();

    if ( level.mv_options.size < 3 )
    {
        println( "[T4 Map Vote] mv_maps needs at least two valid, unique maps." );
        mvLog( "start_vote_failed_map_pool" );
        level.mv_running = false;
        return;
    }

    level.mv_votes = [];
    for ( i = 0; i < level.mv_options.size; i++ )
        level.mv_votes[i] = 0;

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        player = players[i];
        if ( isRealPlayer( player ) )
        {
            player closeMenu();
            player closeInGameMenu();
            player.mv_vote = -1;
            player.mv_cursor = 0;
            player thread createVoteHud();
            player thread handleVoteInput();
        }
    }

    timeLeft = getDvarInt( "mv_time" );
    if ( timeLeft < 5 )
        timeLeft = 20;
    println( "[T4 Map Vote v0.9] Vote timer: " + timeLeft + " seconds" );
    mvLog( "vote_timer_started_" + timeLeft );
    while ( timeLeft > 0 && !level.mv_finished )
    {
        level.mv_time_left = timeLeft;
        level updateAllVoteHuds();
        wait 1;
        timeLeft--;
    }

    if ( level.mv_finished )
    {
        while ( !level.mv_complete )
            wait 0.05;
        return;
    }

    level.mv_time_left = 0;
    level updateAllVoteHuds();
    winner = chooseWinner();
    level finishVote( winner );
}

mvLog( message )
{
    logPrint( "MV;" + message + "\n" );
}

buildMapOptions()
{
    pool = strTok( getDvar( "mv_maps" ), " " );
    clean = [];
    current = getDvar( "mapname" );

    for ( i = 0; i < pool.size; i++ )
    {
        map = normalizeMapId( pool[i] );
        if ( map == "" )
            continue;
        if ( !getDvarInt( "mv_allow_current" ) && map == current )
            continue;
        if ( !getDvarInt( "mv_allow_dlc" ) && isDlcMap( map ) )
            continue;
        if ( arrayContains( clean, map ) )
            continue;
        clean[clean.size] = map;
    }

    options = [];
    totalOptions = getDvarInt( "mv_options" );
    if ( totalOptions < 3 )
        totalOptions = 3;
    if ( totalOptions > 6 )
        totalOptions = 6;

    // Reserve the final card for RANDOM.
    count = totalOptions - 1;
    if ( count > clean.size )
        count = clean.size;

    while ( options.size < count )
    {
        index = randomInt( clean.size );
        options[options.size] = clean[index];
        clean = removeArrayIndex( clean, index );
    }

    // Keep the unshown maps as the pool used when RANDOM wins.
    level.mv_random_pool = clean;
    options[options.size] = "__random__";

    return options;
}

createVoteHud()
{
    self endon( "disconnect" );
    level endon( "mv_cleanup" );

    self.mv_hud = [];

    background = newClientHudElem( self );
    background.horzAlign = "center";
    background.vertAlign = "middle";
    background.alignX = "center";
    background.alignY = "middle";
    background.x = 0;
    background.y = 0;
    background.sort = 1;
    background.alpha = 0.82;
    background.color = ( 0.02, 0.02, 0.025 );
    background setShader( "white", 640, 480 );
    self.mv_hud[self.mv_hud.size] = background;

    title = createFontString( "objective", 2.0 );
    title setPoint( "CENTER", "CENTER", 0, -125 );
    title.sort = 5;
    title.color = ( 0.92, 0.72, 0.20 );
    title setText( "VOTE FOR THE NEXT MAP" );
    self.mv_hud[self.mv_hud.size] = title;

    self.mv_cards = [];
    columns = 3;
    twoRows = level.mv_options.size > 3;
    for ( i = 0; i < level.mv_options.size; i++ )
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
        card.border.sort = 2;
        card.border.alpha = 0.7;
        card.border.color = ( 0.20, 0.20, 0.20 );
        card.border setShader( "white", 130, 98 );
        self.mv_hud[self.mv_hud.size] = card.border;

        card.image = newClientHudElem( self );
        card.image.horzAlign = "center";
        card.image.vertAlign = "middle";
        card.image.alignX = "center";
        card.image.alignY = "middle";
        card.image.x = x;
        card.image.y = y - 7;
        card.image.sort = 3;
        card.image.alpha = 1;
        if ( level.mv_options[i] == "__random__" )
        {
            card.image.color = getCardColor( i );
            card.image setShader( "white", 124, 76 );
        }
        else
        {
            card.image.color = ( 1, 1, 1 );
            card.image setShader( "loadscreen_" + level.mv_options[i], 124, 76 );
        }
        self.mv_hud[self.mv_hud.size] = card.image;

        displayName = getVoteMapName( level.mv_options[i] );
        card.name = createFontString( "default", 1.25 );
        card.name setPoint( "CENTER", "CENTER", x, y + 40 );
        card.name.sort = 5;
        card.name setText( displayName );
        self.mv_hud[self.mv_hud.size] = card.name;

        card.votes = createFontString( "default", 1.15 );
        card.votes setPoint( "CENTER", "CENTER", x + 48, y + 40 );
        card.votes.sort = 6;
        card.votes setValue( 0 );
        self.mv_hud[self.mv_hud.size] = card.votes;

        self.mv_cards[i] = card;
    }

    self.mv_timer = createFontString( "objective", 1.45 );
    if ( twoRows )
        self.mv_timer setPoint( "CENTER", "CENTER", 0, 148 );
    else
        self.mv_timer setPoint( "CENTER", "CENTER", 0, 100 );
    self.mv_timer.sort = 5;
    self.mv_timer setText( "AIM: PREVIOUS   FIRE: NEXT   USE/RELOAD: VOTE" );
    self.mv_hud[self.mv_hud.size] = self.mv_timer;

    credit = createFontString( "default", 1.0 );
    credit setPoint( "CENTER", "CENTER", 0, 205 );
    credit.sort = 5;
    credit.alpha = 0.60;
    credit.color = ( 0.65, 0.65, 0.65 );
    credit setText( "Developed by CUKServers" );
    self.mv_hud[self.mv_hud.size] = credit;

    self updateVoteHud();
}

handleVoteInput()
{
    self endon( "disconnect" );
    level endon( "mv_cleanup" );

    // Prevent a fire/use/reload held during the final kill or round transition
    // from immediately selecting a card.
    wait 1;

    self notifyOnPlayerCommand( "mv_prev", "+speed_throw" );
    self notifyOnPlayerCommand( "mv_next", "+attack" );
    self notifyOnPlayerCommand( "mv_use", "+activate" );
    self notifyOnPlayerCommand( "mv_reload", "+reload" );

    for ( ;; )
    {
        command = self waittill_any_return( "mv_prev", "mv_next", "mv_use", "mv_reload" );

        if ( command == "mv_prev" )
        {
            self.mv_cursor--;
            if ( self.mv_cursor < 0 )
                self.mv_cursor = level.mv_options.size - 1;
        }
        else if ( command == "mv_next" )
        {
            self.mv_cursor++;
            if ( self.mv_cursor >= level.mv_options.size )
                self.mv_cursor = 0;
        }
        else
        {
            self castVote( self.mv_cursor );
        }

        self updateVoteHud();
        wait 0.12;
    }
}

castVote( index )
{
    if ( index < 0 || index >= level.mv_options.size )
        return;

    if ( self.mv_vote >= 0 )
        level.mv_votes[self.mv_vote]--;

    self.mv_vote = index;
    level.mv_votes[index]++;
    level updateAllVoteHuds();
}

updateAllVoteHuds()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
        if ( isRealPlayer( players[i] ) && isDefined( players[i].mv_hud ) )
            players[i] updateVoteHud();
}

updateVoteHud()
{
    if ( !isDefined( self.mv_cards ) )
        return;

    for ( i = 0; i < self.mv_cards.size; i++ )
    {
        if ( i == self.mv_cursor )
        {
            // Blue is navigation only; gold is reserved for the final winner.
            self.mv_cards[i].border.color = ( 0.25, 0.65, 1.0 );
            self.mv_cards[i].border.alpha = 1;
        }
        else
        {
            self.mv_cards[i].border.color = ( 0.20, 0.20, 0.20 );
            self.mv_cards[i].border.alpha = 0.7;
        }

        if ( self.mv_vote == i )
        {
            self.mv_cards[i].name.color = ( 0.35, 1.0, 0.35 );
            self.mv_cards[i].border.color = ( 0.20, 0.75, 0.30 );
        }
        else
            self.mv_cards[i].name.color = ( 1, 1, 1 );

        self.mv_cards[i].votes setValue( level.mv_votes[i] );
    }

    if ( isDefined( self.mv_timer ) && isDefined( level.mv_time_left ) )
        self.mv_timer setText( "AIM: PREVIOUS   FIRE: NEXT   USE/RELOAD: VOTE     TIME: " + level.mv_time_left );
}

finishVote( winner )
{
    chosenMap = "";
    chosenGametype = "";
    rotation = "";
    winnerName = "";

    if ( level.mv_finished )
        return;

    level.mv_finished = true;
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( isRealPlayer( players[i] ) && isDefined( players[i].mv_cards ) )
        {
            players[i].mv_cards[winner].border.color = ( 0.95, 0.68, 0.12 );
            players[i].mv_cards[winner].border.alpha = 1;
        }
    }

    chosenMap = level.mv_options[winner];
    if ( chosenMap == "__random__" )
    {
        if ( level.mv_random_pool.size > 0 )
            chosenMap = level.mv_random_pool[randomInt( level.mv_random_pool.size )];
        else
            chosenMap = level.mv_options[randomInt( level.mv_options.size - 1 )];
    }
    chosenGametype = chooseGametype();
    winnerName = getVoteMapName( chosenMap );

    rotation = "map " + chosenMap;
    if ( chosenGametype != "" )
    {
        setDvar( "g_gametype", chosenGametype );
        rotation = "gametype " + chosenGametype + " " + rotation;
    }

    setDvar( "sv_mapRotationCurrent", rotation );
    setDvar( "sv_mapRotation", rotation );
    println( "[T4 Map Vote] Winner: " + chosenMap + " | Rotation: " + rotation );

    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        if ( isRealPlayer( players[i] ) && isDefined( players[i].mv_timer ) )
        {
            players[i].mv_timer.color = ( 0.35, 1.0, 0.35 );
            players[i].mv_timer setText( "WINNER: " + winnerName );
        }
    }

    resultTime = getDvarInt( "mv_result_time" );
    if ( resultTime < 2 )
        resultTime = 3;
    wait resultTime;
    level notify( "mv_cleanup" );
    level cleanupVoteHuds();
    level.mv_complete = true;
}

cleanupVoteHuds()
{
    players = level.players;
    for ( i = 0; i < players.size; i++ )
    {
        player = players[i];
        if ( !isDefined( player.mv_hud ) )
            continue;
        for ( j = 0; j < player.mv_hud.size; j++ )
            if ( isDefined( player.mv_hud[j] ) )
                player.mv_hud[j] destroy();
        player.mv_hud = undefined;
    }
}

chooseWinner()
{
    best = -1;
    tied = [];
    for ( i = 0; i < level.mv_votes.size; i++ )
    {
        if ( level.mv_votes[i] > best )
        {
            best = level.mv_votes[i];
            tied = [];
            tied[0] = i;
        }
        else if ( level.mv_votes[i] == best )
        {
            tied[tied.size] = i;
        }
    }
    return tied[randomInt( tied.size )];
}

chooseGametype()
{
    gametypes = strTok( getDvar( "mv_gametypes" ), " " );
    if ( gametypes.size == 0 )
        return "";
    return gametypes[randomInt( gametypes.size )];
}

votesNeeded()
{
    humans = 0;
    for ( i = 0; i < level.players.size; i++ )
        if ( isRealPlayer( level.players[i] ) )
            humans++;
    return int( humans / 2 ) + 1;
}

matchWillEnd()
{
    if ( isDefined( level.forcedEnd ) && level.forcedEnd )
        return true;

    // This is the same gate used by T4's stock endGame() before it considers
    // starting another round.
    multiRound = ( level.roundLimit > 1 || ( !level.roundLimit && level.scoreLimit != 1 ) );
    if ( !multiRound )
        return true;

    if ( level.roundLimit > 0 && game["roundsplayed"] >= level.roundLimit )
        return true;

    if ( !level.scoreLimitIsPerRound && level.scoreLimit > 0 )
    {
        if ( level.teamBased )
        {
            if ( game["teamScores"]["allies"] >= level.scoreLimit )
                return true;
            if ( game["teamScores"]["axis"] >= level.scoreLimit )
                return true;
        }
        else
        {
            for ( i = 0; i < level.players.size; i++ )
                if ( isDefined( level.players[i].score ) && level.players[i].score >= level.scoreLimit )
                    return true;
        }
    }

    return false;
}

normalizeMapId( map )
{
    switch ( toLower( map ) )
    {
        case "mp_nightfire": return "mp_nachtfeuer";
        case "mp_station": return "mp_subway";
        case "mp_subpens": return "mp_docks";
        case "mp_sub_pens": return "mp_docks";
        case "mp_banzai": return "mp_kwai";
        case "mp_corrosion": return "mp_stalingrad";
        case "mp_battery": return "mp_drum";
        case "mp_breach": return "mp_bgate";
        case "mp_revolution": return "mp_vodka";
        default: return toLower( map );
    }
}

isDlcMap( map )
{
    switch ( map )
    {
        // Map Pack 1
        case "mp_kneedeep":
        case "mp_nachtfeuer":
        case "mp_subway":
        // Map Pack 2
        case "mp_kwai":
        case "mp_stalingrad":
        case "mp_drum":
        // Map Pack 3
        case "mp_bgate":
        case "mp_vodka":
        case "mp_docks":
            return true;
    }

    return false;
}

getCardColor( index )
{
    switch ( index )
    {
        case 0: return ( 0.20, 0.27, 0.34 );
        case 1: return ( 0.28, 0.22, 0.18 );
        case 2: return ( 0.18, 0.30, 0.22 );
        case 3: return ( 0.30, 0.18, 0.18 );
        case 4: return ( 0.22, 0.20, 0.32 );
        default: return ( 0.30, 0.27, 0.16 );
    }
}

isRealPlayer( player )
{
    if ( !isDefined( player ) || !isPlayer( player ) )
        return false;
    if ( isDefined( player.pers["isBot"] ) && player.pers["isBot"] )
        return false;
    if ( isDefined( player.pers["isBotWarfare"] ) && player.pers["isBotWarfare"] )
        return false;
    return true;
}

setDefaultDvar( name, value )
{
    if ( getDvar( name ) == "" )
        setDvar( name, value );
}

arrayContains( array, value )
{
    for ( i = 0; i < array.size; i++ )
        if ( array[i] == value )
            return true;
    return false;
}

removeArrayIndex( array, index )
{
    result = [];
    for ( i = 0; i < array.size; i++ )
        if ( i != index )
            result[result.size] = array[i];
    return result;
}

getVoteMapName( map )
{
    switch ( map )
    {
        case "__random__": return "RANDOM";
        case "mp_airfield": return "AIRFIELD";
        case "mp_asylum": return "ASYLUM";
        case "mp_castle": return "CASTLE";
        case "mp_courtyard": return "COURTYARD";
        case "mp_dome": return "DOME";
        case "mp_downfall": return "DOWNFALL";
        case "mp_hangar": return "HANGAR";
        case "mp_makin": return "MAKIN";
        case "mp_outskirts": return "OUTSKIRTS";
        case "mp_roundhouse": return "ROUNDHOUSE";
        case "mp_seelow": return "SEELOW";
        case "mp_shrine": return "CLIFFSIDE";
        case "mp_suburban": return "UPHEAVAL";
        case "mp_kneedeep": return "KNEE DEEP";
        case "mp_makin_day": return "MAKIN DAY";
        case "mp_nachtfeuer": return "NIGHTFIRE";
        case "mp_subway": return "STATION";
        case "mp_docks": return "SUB PENS";
        case "mp_kwai": return "BANZAI";
        case "mp_stalingrad": return "CORROSION";
        case "mp_drum": return "BATTERY";
        case "mp_bgate": return "BREACH";
        case "mp_vodka": return "REVOLUTION";
        default: return map;
    }
}

precacheT4Levelshots()
{
    precacheShader( "white" );
    precacheShader( "loadscreen_mp_airfield" );
    precacheShader( "loadscreen_mp_asylum" );
    precacheShader( "loadscreen_mp_castle" );
    precacheShader( "loadscreen_mp_courtyard" );
    precacheShader( "loadscreen_mp_dome" );
    precacheShader( "loadscreen_mp_downfall" );
    precacheShader( "loadscreen_mp_hangar" );
    precacheShader( "loadscreen_mp_makin" );
    precacheShader( "loadscreen_mp_makin_day" );
    precacheShader( "loadscreen_mp_outskirts" );
    precacheShader( "loadscreen_mp_roundhouse" );
    precacheShader( "loadscreen_mp_seelow" );
    precacheShader( "loadscreen_mp_shrine" );
    precacheShader( "loadscreen_mp_suburban" );
    precacheShader( "loadscreen_mp_kneedeep" );
    precacheShader( "loadscreen_mp_nachtfeuer" );
    precacheShader( "loadscreen_mp_subway" );
    precacheShader( "loadscreen_mp_docks" );
    precacheShader( "loadscreen_mp_kwai" );
    precacheShader( "loadscreen_mp_stalingrad" );
    precacheShader( "loadscreen_mp_drum" );
    precacheShader( "loadscreen_mp_bgate" );
    precacheShader( "loadscreen_mp_vodka" );
}
