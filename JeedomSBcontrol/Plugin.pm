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
use Data::Dumper;
use utf8;
use URI::Escape;
my $enc = 'latin-1';
my $jeedomip;
my $jeedomkey;
my $jeedomcomplement;
my $prefs = preferences('plugin.jeedomsbcontrol');
my %data;
my %repeat;
my %shuffle;
our @browseMenuChoices;

my $log = Slim::Utils::Log->addLogCategory({
	'category'	 => 'plugin.jeedomsbcontrol',
	'defaultLevel' => 'INFO',
	'description'  => getDisplayName(),
});

sub roundup {
	my $n = shift;
	return(($n == int($n)) ? $n : int($n + 1))
}

sub getDisplayName {
	return 'PLUGIN_JEEDOMSBCONTROL_NAME';
}

sub myDebug {
	my $msg = shift;
	my $source = shift;
	my $lvl = shift;
	if ($lvl eq "")
	{
		$lvl = "debug";
	}
	$log->$lvl("*** JeedomSbcontrol *** $source $msg");
}

sub sender {
	my $value = shift;
	my $client = shift;
	my $source = shift;
	my $mac = ref($client) ? $client->macaddress() : $client;
	if(!($data{$mac} ~~ $value)){
        $data{$mac} = $value;
        my $http = Slim::Networking::SimpleAsyncHTTP->new(\&exampleCallback,
					\&exampleErrorCallback,{client => $client,});
		myDebug("http://$jeedomip$jeedomcomplement/plugins/squeezeboxcontrol/core/php/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value=$value",$source);
		my $encoded = uri_escape($value);
		$http->get("http://$jeedomip$jeedomcomplement/plugins/squeezeboxcontrol/core/php/squeezeboxcontrolApi.php?api=$jeedomkey&adress=$mac&value=$encoded");
    }else{
        $log->debug('Sending informations NON OK : request already send');
    }
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
	Slim::Control::Request::subscribe( \&commandCallback, [['play', 'pause']]);
	Slim::Control::Request::subscribe( \&powerCallback, [['power']]);
	Slim::Control::Request::subscribe( \&syncCallback, [['sync']]);
	Slim::Control::Request::subscribe( \&commandCallbackShuffle, [['shuffle']]);
	Slim::Control::Request::subscribe( \&commandCallbackRepeat, [['repeat']]);
	Slim::Control::Request::subscribe( \&commandCallbackClient, [['client']]);
}

sub shutdownPlugin {
	Slim::Control::Request::unsubscribe(\&commandCallbackVolume);
	Slim::Control::Request::unsubscribe(\&commandCallback);
	Slim::Control::Request::unsubscribe(\&powerCallback);
	Slim::Control::Request::unsubscribe(\&syncCallback);
	Slim::Control::Request::unsubscribe(\&commandCallbackShuffle);
	Slim::Control::Request::unsubscribe(\&commandCallbackRepeat);
	Slim::Control::Request::unsubscribe(\&commandCallbackClient);
}

sub syncCallback {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
			return;
	}
	$log->debug("Callback on sync");
	&handlePlayTrack($client,'sync');
}

sub commandCallbackClient {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
			return;
	}
	$log->debug("Callback on client");
	&handlePlayTrack($client,'client');
}

sub commandCallbackShuffle {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
		return;
	}
	$log->debug("Callback on shuffle");
	&handlePlayTrack($client,'shuffle');
}

sub commandCallbackRepeat {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
		return;
	}
	$log->debug("Callback on repeat");
	&handlePlayTrack($client,'repeat');
}

sub commandCallbackVolume {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
		return;
	}
	$log->debug("Callback on volume");
	&handlePlayTrack($client,'volume');
}

sub commandCallbackNewsong {
	my $request = shift;
	my $client = $request->client();
	if( !defined( $client)) {
			return;
	}
	$log->debug("Callback on newsong");
	&handlePlayTrack($client,'newsong');
}

sub commandCallback {
	my $request = shift;
	my $client = $request->client();
        my $iPower = $client->power();
	if( !defined( $client)) {
		return;
	}
	if(($request->isCommand([['playlist'], ['newsong']])) || ($request->isCommand([['play']])) || ($request->isCommand([['pause']]))  || ($request->isCommand([['playlist'], ['stop']]))) {
		if ($iPower == 1){
			$log->debug("Callback on callback");;
			&handlePlayTrack($client,'callback');
		}
	} else {
		$log->debug(Dumper($request));
	}
}

sub powerCallback {
	my $request = shift;
	my $client = $request->client();
	my $iPower = $client->power();
	my $iSyncedPlayer = $client->isSynced() ;
	my $tosend='';
	my @SyncedSlaves ;
	$log->debug("Callback on power");
	if ($iPower == 1){
		&handlePlayTrack($client);
	} else{
		sender("{\"statut\":\"Off\",\"etat\":\"Off\"}",$client,"powerCallback");
		if ($iSyncedPlayer ==1 ){
			@SyncedSlaves = Slim::Player::Sync::slaves($client);
			foreach my $slaveclient (@SyncedSlaves) {
				my $iPower = $slaveclient->power();
				if ($iPower == 1){
					&handlePlayTrack($slaveclient,'power');
				} else {
					sender("{\"statut\":\"Off\",\"etat\":\"Off\"}",$slaveclient,"powerCallbackSync");
				}
			}
		}
	}
}

sub handlePlayTrack {
	my $client = shift;
	my $from = shift;
	my $iSyncedPlayer = $client->isSynced() ;
	my $iPower = $client->power();
	my $iMaster = Slim::Player::Sync::isMaster($client);
	my @iSyncedMaster = $client->master();
	my @SyncedSlaves ;
	my $sTitle = $client->playingSong();
	my $sName =  'Aucun';
	my $artist   = 'Aucun';
	my $album	= 'Aucun';
	my $iVolume = $client->volume();
	my $tempVolume = $client->tempVolume();
	my $status = '';
	my $etat = 'On';
	my $sync_status = 0;
	my $repeat_status = Slim::Player::Playlist::repeat($client);
	my $shuffle_status = Slim::Player::Playlist::shuffle($client);
	my $mac = ref($client) ? $client->macaddress() : $client;
	if(defined($sTitle)) {
		eval {$sName =  $sTitle->track()->title  || ''; }; warn $@ if $@;
		eval { $artist   = $sTitle->track()->artistName || '';}; warn $@ if $@;
		eval { $album	= $sTitle->track()->album  ? $sTitle->track()->album->name  : '';}; warn $@ if $@;
		$artist	 = encode('UTF-8', $artist);
		$album	 = encode('UTF-8', $album);
		$sName	 = encode('UTF-8', $sName);
		my $remoteMeta;
		my $handler;
		$handler = Slim::Player::ProtocolHandlers->handlerForURL($sTitle->track()->url);
		if ( $handler && $handler->can('getMetadataFor') ) {
			$remoteMeta = $handler->getMetadataFor($client,$sTitle->track()->url );
			$album = $sName;
			if(defined( $remoteMeta->{album})) {
				$album = encode('UTF-8', $remoteMeta->{album});
			}
			$artist = encode('UTF-8', $remoteMeta->{artist});
			$sName = encode('UTF-8', $remoteMeta->{title});
		}
	}
	my $iPaused = $client->isPaused();
	my $iStopped = $client->isStopped();
	if($iPower ==  1) {
		if($iPaused ne  1) {
			if ($iStopped == 1){
				$status = "Stop";
			}else{
				$status = "Lecture";
			}
		}else{
			$status = "Pause";
		}
	}else{
		$status = "Off";
		$etat = "Off";
	}
	my $volume = $iVolume;
	if ($iSyncedPlayer == 1 ){
		$sync_status = 1;
		@SyncedSlaves = Slim::Player::Sync::slaves($client);
		my $slave_json;
		my $macmaster;
		my $master_name;
		foreach my $slaveclient (@SyncedSlaves) {
			my $macslave = ref($slaveclient) ? $slaveclient->macaddress() : $slaveclient;
			$slave_json .= "{\"mac\":\"$macslave\"},";
		}
		$slave_json = substr $slave_json, 0, -1;
		foreach my $masterclient (@iSyncedMaster) {
			$macmaster = ref($masterclient) ? $masterclient->macaddress() : $masterclient;
			$volume = $masterclient->volume();
			if (!($volume =~ /^\d+$/)){
				$volume = 'old';
			}
			if ($from ~~ "volume") {
				sender("{\"volume\":\"$volume\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
			} elsif ($from ~~ 'repeat') {
				sender("{\"repeat\":\"$repeat_status\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
			} elsif ($from ~~ 'shuffle') {
				sender("{\"shuffle\":\"$shuffle_status\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
			} else {
				if (exists($shuffle{$mac}) && !($shuffle{$mac} ~~ $shuffle_status)){
					sender("{\"shuffle\":\"$shuffle_status\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
				} elsif (exists($repeat{$mac}) && !($repeat{$mac} ~~ $repeat_status)){
					sender("{\"repeat\":\"$repeat_status\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
				} else {
					sender("{\"repeat\":\"$repeat_status\",\"shuffle\":\"$shuffle_status\",\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"$status\",\"etat\":\"$etat\",\"sync\":{\"master\":\"null\",\"slave\":[$slave_json]}}",$masterclient,"handlermaster");
				}
			}
		}
		foreach my $slaveclient (@SyncedSlaves) {
			$volume = $slaveclient->volume();
			if (!($volume =~ /^\d+$/)){
				$volume = 'old';
			}
			if ($from ~~ "volume") {
				sender("{\"volume\":\"$volume\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
			} elsif ($from ~~ 'repeat') {
				sender("{\"repeat\":\"$repeat_status\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
			} elsif ($from ~~ 'shuffle') {
				sender("{\"shuffle\":\"$shuffle_status\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
			} else {
				if (exists($shuffle{$mac}) && !($shuffle{$mac} ~~ $shuffle_status)){
					sender("{\"shuffle\":\"$shuffle_status\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
				} elsif (exists($repeat{$mac}) && !($repeat{$mac} ~~ $repeat_status)){
					sender("{\"repeat\":\"$repeat_status\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
				} else {
					sender("{\"repeat\":\"$repeat_status\",\"shuffle\":\"$shuffle_status\",\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"$status\",\"etat\":\"$etat\",\"sync\":{\"master\":{\"mac\":\"$macmaster\"},\"slave\":[$slave_json]}}",$slaveclient,"handlerslave");
				}
			}
		}
	}else{
		if (!($volume =~ /^\d+$/)){
				$volume = 'old';
			}
		if ($from ~~ "volume") {
			sender("{\"volume\":\"$volume\"}",$client,"handler");
		} elsif ($from ~~ 'repeat') {
			sender("{\"repeat\":\"$repeat_status\"}",$client,"handler");
		} elsif ($from ~~ 'shuffle') {
			sender("{\"shuffle\":\"$shuffle_status\"}",$client,"handler");
		} else {
			if (exists($shuffle{$mac}) && !($shuffle{$mac} ~~ $shuffle_status)){
				sender("{\"shuffle\":\"$shuffle_status\"}",$client,"handler");
			} elsif (exists($repeat{$mac}) && !($repeat{$mac} ~~ $repeat_status)){
				sender("{\"repeat\":\"$repeat_status\"}",$client,"handler");
			} else {
				sender("{\"repeat\":\"$repeat_status\",\"shuffle\":\"$shuffle_status\",\"titre\":\"$sName\",\"artist\":\"$artist\",\"album\":\"$album\",\"statut\":\"$status\",\"etat\":\"$etat\",\"sync\":\"null\"}",$client,"handler");
			}
		}
		$repeat{$mac} = $repeat_status;
		$shuffle{$mac} = $shuffle_status;
	}
}

sub exampleCallback {

}

sub exampleErrorCallback {

}
1;
