# Expose-Round-State

This is a sourcemod plugin that will expose certain data about a round and its state as an external API, directly addressable as if it were a webpage hosted by SRCDS itself.

## Dependencies

- [Sourcemod 1.11](https://www.sourcemod.net/downloads.php?branch=stable) or higher (tested on build 6923)
- [sm-json](https://github.com/clugg/sm-json) library version 5.0.0 or higher
- The JoinedSenses fork of [sm-ext-socket](https://github.com/JoinedSenses/sm-ext-socket/) tested against the release on Nov 18, 2019.
- [This](https://github.com/powerlord/sourcemod-snippets/blob/5bbc8e384d4b0dde8fe76868af7ce7e6909e9855/scripting/include/tf2_morestocks.inc#L277-L408) snippet of code from powerlord's snippets repo. (tf2_morestocks.inc)
- A server host that doesn't mind you creating a socket to listen on a port other than your server's assigned port.

The sourcemod version, socket extension, and the server thing are mandatory for runtime. Everything but the server thing is mandatory for compilation.

I've tried my hardest to supreses IDE issues... no I haven't. I don't care. I'm sending HTTP/1.0 messages from TF2. Bite me.

## Scope of this Project

Before you ask, no. This will NOT be a fully fledged web server or reverse proxy operating in Sourcemod. I think it's doable in sourcemod, but I don't want to achieve that. I want to expose a few things about the round state and that's it. I don't want to have to deal with the complexities of HTTP/1.1, or the complexities of a full web server.

## License

GNU Public 3.0. See [LICENSE](/LICENSE) for more information. Realistically I don't care what you use this for. Just as long as you don't expect me to maintain it.
