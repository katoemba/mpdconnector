# README #

### What is this repository for? ###

* MPDConnector is an implementation of the generic ConnectorProtocol interface specification to control a network based music player.
The implementation uses libmpdclient to control mpd-based players of version 0.19 and up.
* These two frameworks are the foundation of the Rigelian MPD client, for more info see http://www.rigelian.net

### What are the building blocks of this Library? ###

* The implementation relies heavily on reactive constructs, using RxSwift.
* ConnectorProtocol consist of five sub-protocols, all of which are implemented in this framework:
	  * PlayerProtocol defines a basic player, access status, control and browse implementation, plus functions to maintain player-specific settings.
	  * PlayerBrowserProtocol is a generic protocol to detect players on the network.
	  * StatusProtocol is a protocol through which the connection status of a player, as well as the music-playing status can be monitored.
	  * ControlProtocol is a protocol through which commands can be sent to a player, like play, pause, add a song etc.
	  * BrowseProtocol is a protocol through which you can browse through the music on a player. It defines various ViewModels for artists, albums, genres etc.
* The protocol is meant to be independent of the target platform (iOS, MacOS, tvOS). However testing is only done on iOS.

### How do I get set up? ###

* For now you will have to manually copy MPDConnector into a project.
* MPDConnector depends on the following libraries:
	* ConnectorProtocol https://bitbucket.org/musicremote/connectorprotocol/
    * RxSwift v4
    * RxCocoa v4
    * RxDataSources v3
	* RxBlocking v4 for the unit test part

### Testing ###

* A set of unit tests is included, with limited coverage.

### Who do I talk to? ###

* In case of questions you can contact berrie at rigelian dot net