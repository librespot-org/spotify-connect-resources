# spotify-connect-resources
A repository to hold any data/stuff related to reversing the Spotify Connect protocol. Mostly just data dumps at the moment, but if you have something to add to it, be it an implementation, information or just another data dump, make a PR and I will add it asap.

Currently this repo holds a few data dumps, and links to other sites which have also made headway on reversing the Connect protocol. Due to the current lack of common meeting ground atm, I have created this repo, so please feel free to PR anything Connect related. Also, you are encouraged to join the Spotify Connect room on Gitter (UPDATE: We now have IRC aswell, see below), as it is by far the easiest wat to connect with others interested in reversing Connect, and keeping up with current progress. The room is available here:

[![Gitter](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/sashahilton00/spotify-connect-resources?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![IRC](https://img.shields.io/badge/IRC-Freenode-brightgreen.svg)](https://webchat.freenode.net/)

IRC:

Server: irc.freenode.net
Channel: #spotifyconnect

**If you are looking for (working) implementations of Spotify Connect, they can be found here:**

https://github.com/plietar/librespot (Rust/C)  
https://github.com/crsmoro/scplayer (Java) (This version is not open source. It uses the libraries etracted from firmware.)
https://github.com/Fornoth/spotify-connect-web (As above, uses the extracted libraries. Has a nice web interface.)
https://github.com/dtcooper/raspotify (Wrapper for librespot) \
https://github.com/spocon/spocon (Debian/Ubuntu package wrapper [librespot-java](https://github.com/librespot-org/librespot-java) - includes armhf,arm64,armel)

N.B. The libraries are nearing release. There are a few bugs and features that still need implementing, but it's mostly done. If someone wants to start on a wrapper for the rust library, drop into the chat.

There is also a project which only implements control of Spotify Connect devices:

https://github.com/badfortrains/spotcontrol

If you just want to compile and run, take a look at the documentation in the spotify-connect folder.
Any contributions welcome. If you would like to get a working prototype with web interface running, have a look at the spotify-connect-web directory.

--ATTENTION: the spotify-connect folder holds a working implementation of Spotify Connect, so if you wish to help with development, please add your contributions there.--
