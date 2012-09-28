describe 'An IRC client', ->
  irc = socket = chat = undefined

  waitsForArrayBufferConversion = () ->
    waitsFor (-> not window.irc.util.isConvertingArrayBuffers()),
      'wait for array buffer conversion', 500

  resetSpies = () ->
    socket.connect.reset()
    socket.received.reset()
    socket.close.reset()
    chat.onConnected.reset()
    chat.onIRCMessage.reset()
    chat.onJoined.reset()
    chat.onParted.reset()
    chat.onDisconnected.reset()

  beforeEach ->
    jasmine.Clock.useMock()
    socket = new net.MockSocket
    irc = new window.irc.IRC socket
    chat = new window.chat.MockChat irc

    spyOn(socket, 'connect')
    spyOn(socket, 'received').andCallThrough()
    spyOn(socket, 'close').andCallThrough()

    spyOn(chat, 'onConnected')
    spyOn(chat, 'onIRCMessage')
    spyOn(chat, 'onJoined')
    spyOn(chat, 'onParted')
    spyOn(chat, 'onDisconnected')

  it 'is initially disconnected', ->
    expect(irc.state).toBe 'disconnected'

  it 'does nothing on non-connection commands when disconnected', ->
    irc.quit()
    irc.giveup()
    irc.doCommand 'NICK', 'sugarman'
    waitsForArrayBufferConversion()
    runs ->
      expect(irc.state).toBe 'disconnected'
      expect(socket.received).not.toHaveBeenCalled()

  describe 'that is connecting', ->

    beforeEach ->
      irc.setPreferredNick 'sugarman'
      irc.connect 'irc.freenode.net', 6667
      expect(irc.state).toBe 'connecting'
      socket.respond 'connect'
      waitsForArrayBufferConversion()

    it 'is connecting to the correct server and port', ->
      expect(socket.connect).toHaveBeenCalledWith('irc.freenode.net', 6667)

    it 'sends NICK and USER', ->
      runs ->
        expect(socket.received.callCount).toBe 2
        expect(socket.received.argsForCall[0]).toMatch /NICK sugarman\s*/
        expect(socket.received.argsForCall[1]).toMatch /USER sugarman 0 \* :.+/

    it 'appends an underscore when the desired nick is in use', ->
      socket.respondWithData ":irc.freenode.net 433 * sugarman :Nickname is already in use."
      waitsForArrayBufferConversion()
      runs ->
        expect(socket.received.mostRecentCall.args).toMatch /NICK sugarman_\s*/

    describe 'then connects', ->

      joinChannel = (chan, nick='sugarman') ->
        socket.respondWithData ":#{nick}!sugarman@company.com JOIN :#{chan}"
        waitsForArrayBufferConversion()

      beforeEach ->
        resetSpies()
        socket.respondWithData ":cameron.freenode.net 001 sugarman :Welcome"
        waitsForArrayBufferConversion()

      it "is in the 'connected' state", ->
        runs ->
          expect(irc.state).toBe 'connected'

      it 'emits connect', ->
        runs ->
          expect(chat.onConnected).toHaveBeenCalled()

      it 'emits a welcome message', ->
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalled()
          args = chat.onIRCMessage.mostRecentCall.args
          expect(args[0]).toBeUndefined() # channel
          expect(args[1]).toBe 'welcome' # type
          expect(args[2]).toEqual jasmine.any String # message

      it "properly creates commands on doCommand()", ->
        irc.doCommand 'JOIN', '#awesome'
        irc.doCommand 'PRIVMSG', '#awesome', 'hello world'
        irc.doCommand 'NICK', 'sugarman'
        irc.doCommand 'PART', '#awesome', 'this channel is not awesome'
        waitsForArrayBufferConversion()
        runs ->
          expect(socket.received.callCount).toBe 4
          expect(socket.received.argsForCall[0]).toMatch /JOIN #awesome\s*/
          expect(socket.received.argsForCall[1]).toMatch /PRIVMSG #awesome :hello world\s*/
          expect(socket.received.argsForCall[2]).toMatch /NICK sugarman\s*/
          expect(socket.received.argsForCall[3]).toMatch /PART #awesome :this channel is not awesome\s*/

      it "emits 'join' after joining a room", ->
        joinChannel('#awesome')
        runs ->
          expect(chat.onJoined).toHaveBeenCalled()

      it "emits a message when someone else joins a room", ->
        joinChannel '#awesome'
        joinChannel '#awesome', 'bill'
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'join', 'bill'

      it "responds to a PING with a PONG", ->
        socket.respondWithData "PING :#{(new Date()).getTime()}"
        waitsForArrayBufferConversion()
        runs ->
          expect(socket.received.callCount).toBe 1
          expect(socket.received.mostRecentCall.args).toMatch /PONG \d+\s*/

      it "sends a PING after a long period of inactivity", ->
        jasmine.Clock.tick(80000)
        waitsForArrayBufferConversion()
        runs ->
          expect(socket.received.callCount).toBe 1 # NICK, USER and now PING
          expect(socket.received.mostRecentCall.args).toMatch /PING \d+\s*/

      it "doesn't send a PING if regularly active", ->
        jasmine.Clock.tick(50000)
        socket.respondWithData "PING :#{(new Date()).getTime()}"
        jasmine.Clock.tick(50000)
        irc.doCommand 'JOIN', '#awesome'
        waitsForArrayBufferConversion() # wait for JOIN
        runs ->
          jasmine.Clock.tick(50000)
          waitsForArrayBufferConversion() # wait for possible PING
          runs ->
            expect(socket.received.callCount).toBe 2

      it "can disconnected from the server on /quit", ->
        irc.quit 'this is my reason'
        waitsForArrayBufferConversion()
        runs ->
          expect(socket.received.callCount).toBe 1
          expect(socket.received.mostRecentCall.args).toMatch /QUIT :this is my reason\s*/
          expect(irc.state).toBe 'disconnected'
          expect(socket.close).toHaveBeenCalled()

      it "emits 'topic' after someone sets the topic", ->
        joinChannel '#awesome'
        socket.respondWithData ":sugarman_i!~sugarman@09-stuff.company.com TOPIC #awesome :I am setting the topic!"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'topic', 'sugarman_i',
              'I am setting the topic!'

      it "emits 'topic' after joining a room with a topic", ->
        joinChannel '#awesome'
        socket.respondWithData ":freenode.net 332 sugarman #awesome :I am setting the topic!"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'topic', undefined,
              'I am setting the topic!'

      it "emits 'topic' with no topic argument after receiving rpl_notopic", ->
        joinChannel '#awesome'
        socket.respondWithData ":freenode.net 331 sugarman #awesome :No topic is set."
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'topic', undefined, undefined

      it "emits a 'kick' message when receives KICK for someone else", ->
        joinChannel '#awesome'
        socket.respondWithData ":jerk!user@65.93.146.49 KICK #awesome someguy :just cause"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'kick',
              'jerk', 'someguy', 'just cause'

      it "emits 'part' and a 'kick' message when receives KICK for self", ->
        joinChannel '#awesome'
        socket.respondWithData ":jerk!user@65.93.146.49 KICK #awesome sugarman :just cause"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'kick',
              'jerk', 'sugarman', 'just cause'
          expect(chat.onParted).toHaveBeenCalledWith '#awesome'

      it "emits 'error' with the given message when doing a command without privilege", ->
        joinChannel '#awesome'
        socket.respondWithData ":freenode.net 482 sugarman #awesome :You're not a channel operator"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'error',
              "You're not a channel operator"

      it "emits a message when someone is given channel operator status", ->
        joinChannel '#awesome'
        socket.respondWithData ":nice_guy!nice@guy.com MODE #awesome +o sugarman"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'mode', 'nice_guy',
              'sugarman', '+o'

      it "emits a notice when user's nick is changed", ->
        socket.respondWithData ":sugarman!user@company.com NICK :newnick"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith undefined, 'nick_changed', 'newnick'

      it "doesn't try to set nick name to own nick name on 'nick in use' message", ->
        irc.doCommand 'NICK', 'sugarman_'
        socket.respondWithData "sugarman!user@company.com NICK :sugarman_"
        irc.doCommand 'NICK', 'sugarman'
        data = ":irc.freenode.net 433 * sugarman_ sugarman :Nickname is already in use."
        socket.respondWithData data
        waitsForArrayBufferConversion()
        runs ->
          expect(socket.received.mostRecentCall.args).toMatch /NICK sugarman__\s*/

      it "emits a notice when a private message is received", ->
        socket.respondWithData ":someguy!user@company.com PRIVMSG #awesome :hi!"
        waitsForArrayBufferConversion()
        runs ->
          expect(chat.onIRCMessage).toHaveBeenCalledWith '#awesome', 'privmsg', 'someguy', 'hi!'
