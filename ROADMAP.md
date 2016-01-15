Roadmap:

~~Get a copy of libspotify_embedded_shared.so and the relevant binaries.~~

~~Work out function calls in library, and what they do.~~

~~Implement interface to the library API.~~

~~Work out communication protocol and crypto~~.

~~Implement prototype~~

~~Figure out audio crypto.~~

~~Integrate audio crypto into prototype.~~

Make prototype stable and iron out errors/add functionality. ~~Also remove proprietary dependencies.~~

Create a C wrapper for librespot, and add callbacks so that external programs using the library can detect when music has started/stopped/etc.

Release initial official client library.

Reach stable official client, complete with full functionality and cross platform compatibility.

Who knows what else awaits?

###UPDATE 2/12/15: 

Lots has been going on. Plietar has created the first implementation of a library, located in the librespot directory. The library is mostly there, but there are a few small things that have yet to be worked out, such as, how does Spotify sync play queues? (Anyone at Spotify DevOps, throw us a bone in the chat please :) ) Also, Crsmoro has created a Java implementation of Spotify Connect, which I have yet to test, but from what I have heard, it is relatively stable. So we are edging closer to a release client. If anyone knows Rust, and fancies a weekend project, there are a few things that need to be ironed out in librespot, and a C wrapper needs to be written for the rust library so that it can be used in other projects. In the meantime, I hope everyone is gearing up for a merry Christmas :)

###UPDATE 18/03/15: 

Plenty of progress has occurred on the spotify-connect repo; spotify.h now contains a near complete implementation of an interface to the libspotify_embedded_shared.so library.
We have now managed to work out the communication protocol for playback control (hermes/mercury), and have a semi-functional system in play, we're just working on understanding the last few bits.
The general consensus for the project seems to be that we might as well go the whole hog, so next up is the audio crypto layer. I have found a couple of references to SpotifyCipher::decryptXTEA, so hopefully we're on to something there, fingers crossed.

###UPDATE 16/03/15: 

Due to plietar’s efforts, we now have a pretty good idea of the encryption routine used for playback control in Spotify Connect. Anyone who is handy with cryptography, specifically anyone who could provide some information/assistance surrounding the Shannon cipher, head on over to the chatroom. With a bit of luck, we should soon have the encryption implemented, at which point we can start thinking about either reversing further (audio streams), or just creating a wrapper around libspotify. Who knows what lies ahead :)

###13/03/15:

At this stage, we need to analyse numerous elements involved with libspotify_embedded, including the following:

#The Web API:

We need to look into how libspotify communicates with Spotify servers. As mentioned by @plietar, the communication seems to be based on protobuf, and we believe it to be controlled by GAIA, a proprietary communication protocol found in libspotify_embedded. This will need to be reversed and documented if we are to be able to stream audio.
For info on the protobuf schemas, have a look at the work on this repo: https://github.com/TooTallNate/node-spotify-web and here: https://gist.github.com/adammw/9706428
N.B. We do not know if these schemas are the same used in libspotify_embedded, but the debug output suggests they are.

###Spotify Connect control
This also looks like it is controlled through GAIA, via SpircManager. It appears that once a connection to a Connect speaker has been done over the local network, all playback control is done through Spotify servers. Again, this needs to be reversed and documented.

###API endpoints
We don't know if these are different from the ones used by desktop Spotify and play.spotify.com, so any information and documentation on that would be helpful.

#The Libspotify_Embedded library:

###Function documentation
A list of the main functions can be found here: http://divideoverflow.com/2014/08/reversing-spotify-connect/ but this is by no means exhaustive. Thorough documentation and code is definitely needed before we can think of getting a stable, working solution in place.
@plietar has already started work here: https://github.com/plietar/spotify-connect, a copy of which is available here: https://github.com/sashahilton00/spotify-connect-resources/tree/master/spotify-connect so by all means continue development on that. NB. It is @plietar's work, copied here for centralization purposes.

---

Any other contributions regarding libspotify_embedded are also welcome, just submit a pr to the repo ;)
For the sake of consistency, please use the rocki or powernode libspotify_embedded where possible, so that we all have the same environment, and (mostly) do not run into errors that differ due to different libraries.

Please post any useful info to the gitter chat, found here: https://gitter.im/sashahilton00/spotify-connect-resources as it just makes keeping track of development much easier.

More updates coming soon, once we have a grip on the current things that need to be done.
