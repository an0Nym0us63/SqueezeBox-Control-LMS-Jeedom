package Plugins::JeedomSBcontrol::Plugin;
use strict;
use base qw(Slim::Plugin::Base);
use Plugins::JeedomSBcontrol::Settings;
use Slim::Music::Info;
use Encode qw(encode decode);;
use Slim::Utils::Misc;
use Slim::Utils::Network;
use Slim::Player::Player;
use Slim::Player::Client;
use Slim::Player::Sync;
use Scalar::Util qw(blessed);
use Slim::Control::Request;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);
use utf8;
use URI::Escape;
my $enc = 'latin-1';
my $jeedomip;
my $jeedomkey;
my $jeedomcomplement;
my $prefs = preferences('plugin.jeedomsbcontrol');

our @browseMenuChoices;

my $log = Slim::Utils::Log->addLogCategory({
	'category'	 => 'plugin.jeedomsbcontrol',
	'defaultLevel' => 'INFO',
	'description'  => getDisplayName(),
});

sub getDisplayName {
	return 'PLUGIN_JEEDOMSBCONTROL_NAME';
}

sub myDebug {
	my $msg = shift;
	my $lvl = shift;
	if ($lvl eq "")
	{
		$lvl = "debug";
	}
	$log->$lvl("*** JeedomSbcontrol *** $msg");
}

sub initPlugin {

	$jeedomip =	$prefs->get('ip');
	$jeedomkey  =	$prefs->get('key');
	$jeedomcomplement  =	$prefs->get('complement');
	my $class = shift;
	myDebug("Initializing");
	$class->SUPER::initPlugin();
	Plugins::JeedomSBcontrol::Settings->new;
	Slim::Control::Request::subscribe( \&commandCallbackVolume, [['mixer']]);
	Slim::Control::Request::subscribe( \&commandCallbackNewsong, [['playlist'], ['newsong']]);
	Slim::Control::Request::subscribe( \&commandCallback, [['play', 'playlist', 'pause']]);
	Slim::Control::Request::subscribe( \&powerCallback, [['power']]);
	Slim::Control::Request::subscribe( \&syncCallback, [['sync']]);
	Slim::Control::Request::subscribe( \&commandCallbackShuffle, [['shuffle']]);
	Slim::Control::Request::subscribe( \&commandCallbackRepeat, [['repeat']]);

}

sub shutdownPlugin {

	Slim::Control::Request::unsubscribe(\&commandCallbackVolume);
	Slim::Control::Request::unsubscribe(\&commandCallbackNewsong);
	Slim::Control::Request::unsubscribe(\&commandCallback);
	Slim::Control::Request::unsubscribe(\&powerCallback);
	Slim::Control::Request::unsubscribe(\&syncCallback);
	Slim::Control::Request::unsubscribe(\&commandCallbackShuffle);
	Slim::Control::Request::unsubscribe(\&commandCallbackRepeat);

}

sub syncCallback {
		my $request = shift;
		my $client = $request->client();
		if( !defined( $client)) {
				return;
		}
		my $mac = ref($client) ? $client->macaddress() : $client;
		my $synced = "|";
		my $controller = $client->controller();
		if( scalar $controller->allPlayers() > 1 && $client != $controller->master()) {
			return;
		}
		for my $other ($client->syncedWith()) {
			my $othermac = ref($other) ? $other->macaddress() : $other;
			$synced = $synced . $othermac . "|";
		}
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,
			\&exampleErrorCallback,{client => $client,});
		$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"synced\":\"$synced\"}");
}

sub commandCallbackRepeat {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
		return;
	}
	my $iPower = $client->power();
	my $iVolume = $client->volume();
			my $mac = ref($client) ? $client->macaddress() : $client;
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,
			\&exampleErrorCallback,{client => $client,});
			$log->error("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"volume\":\"$iVolume\"}");
			$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"volume\":\"$iVolume\"}");
}

sub commandCallbackVolume {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
		return;
	}
	my $iPower = $client->power();
	if( $request->isCommand([['mixer'], ['volume']])  ) {
		if($iPower ==  1) {
			my $iVolume = $client->volume();
			my $mac = ref($client) ? $client->macaddress() : $client;
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,
			\&exampleErrorCallback,{client => $client,});
			$log->error("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"volume\":\"$iVolume\"}");
			$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"volume\":\"$iVolume\"}");
		}
	}
}

sub commandCallbackNewsong {
		my $request = shift;
		my $client = $request->client();
		if( !defined( $client)) {
				return;
		}
		my $r = $client->execute(['status', '-', 1, 'tags:aKl']);
		my $track = $r->getResult('playlist_loop')->[0];
		if( $request->isCommand([['playlist'], ['newsong']]) ) {
			my $sTitle = $client->playingSong();
			my $sName =  'Aucun';
			my $artist   = '';
			my $album	= '';
			my $tracknum = '';
			my $duration =  0;
			my $played =  0;
			
			my $artist = $track->{artist};
			my $album = $track->{album};
			my $sName = $track->{title};

			my $mac = ref($client) ? $client->macaddress() : $client;
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});

			$http->get("http://$jeedomip$jeedomcomplement/core/api/jeeApi.php?api=$jeedomkey&type=squeezeboxcontrol&adress=$mac&value={\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"Lecture\"}");
		}
}

sub commandCallback {
	my $request = shift;
	my $client = $request->client();
	my $iPower = $client->power();
	if( !defined( $client)) {
		return;
	}
	my $iPaused = $client->isPaused();
	my $iStopped = $client->isStopped();
	if (($request->isCommand([['pause'] ]) 
		|| $request->isCommand([['playlist'], ['pause']])) && $iPower == 1){
		if($iPaused ==  1 ) {
			my $mac = ref($client) ? $client->macaddress() : $client;
			my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});
			$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"statut\":\"Pause\",\"titre\":\"Pause\",\"artist\":\"En\",\"album\":\"Aucun\"}");
		}
	}	
	 elsif( $request->isCommand([['play']])
		|| $request->isCommand([['playlist'], ['play']])
		|| $request->isCommand([['playlist'], ['resume']])){
		my $r = $client->execute(['status', '-', 1, 'tags:aKl']);
		my $track = $r->getResult('playlist_loop')->[0];
		my $sTitle = $client->playingSong();
		my $sName =  'Aucun';
		my $artist   = '';
		my $album	= '';
		my $tracknum = '';
		my $duration =  0;
		my $played =  0;
		my $artist = $track->{artist};
		my $album = $track->{album};
		my $sName = $track->{title};
		my $mac = ref($client) ? $client->macaddress() : $client;
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});

		$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"Lecture\"}");
	}
	 elsif( $request->isCommand([['playlist'], ['stop']]) || $request->isCommand([['playlist'], ['clear']]) ) {
		if ($iStopped == 1){
			&handlePlayStop($client);
		}
	}
}

sub powerCallback {
	my $request = shift;
	my $client = $request->client();
	my $iPower = $client->power();
	my $mac = ref($client) ? $client->macaddress() : $client;
	
	if ($iPower == 1){
		my $r = $client->execute(['status', '-', 1, 'tags:aKl']);
		my $track = $r->getResult('playlist_loop')->[0];
		my $sTitle = $client->playingSong();
		my $sName =  'Aucun';
		my $artist   = '';
		my $album	= '';
		my $tracknum = '';
		my $duration =  0;
		my $played =  0;
		my $artist = $track->{artist};
		my $album = $track->{album};
		my $sName = $track->{title};
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});
		if ($sName == ''){
			$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"statut\":\"On\",\"titre\":\"Allume\",\"artist\":\"SqueezeBox\",\"album\":\"Aucun\"}");
		} else {
			$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"Lecture\"}");
		}
	}
	else{
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});
		$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"statut\":\"Off\",\"titre\":\"Eteinte\",\"artist\":\"SqueezeBox\",\"album\":\"Aucun\"}");
	}
}

sub handlePlayStop {
	my $client = shift;
	my $iPower = $client->power();
	my $mac = ref($client) ? $client->macaddress() : $client;

	if ($iPower == 1){
		my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,\&exampleErrorCallback,{client => $client,});
		$http->get("http://$jeedomip$jeedomcomplement/squeezeboxcontrol/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value={\"statut\":\"Stop\",\"titre\":\"Arret\",\"artist\":\"SqueezeBox\",\"album\":\"Aucun\"}");
	}

}

sub exampleCallback {

}

sub exampleErrorCallback {

}
1;
