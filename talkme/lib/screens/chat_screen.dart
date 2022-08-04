import 'dart:convert';
import 'package:talkme/models/connection.dart';
import 'package:talkme/models/socket_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// ignore: must_be_immutable
class ChatScreen extends StatefulWidget {
  ChatScreen({Key? key, required String room})
      : roomId = room,
        super(key: key);
  String roomId;
  @override
  ChatScreenState createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  bool _offer = false;
  bool _isAudioEnabled = true;
  //RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer(); // for Video Call

  late IO.Socket socket;
  bool refresshVideoList = true;

  //final String socketId = "1011";

  final Map<String, dynamic> configuration = {
    "iceServers": [
      {"url": "stun:stun.l.google.com:19302"},
      {
        "url": 'turn:192.158.29.39:3478?transport=udp',
        "credential": 'JZEOEt2V3Qb0y27GRntt2u2PAYA=',
        "username": '28224511:1379330808'
      }
    ]
  };

  final Map<String, dynamic> offerSdpConstraints = {
    "mandatory": {
      "OfferToReceiveAudio": true,
      "OfferToReceiveVideo": true, //for video call
    },
    "optional": [],
  };

  Map<String, Connection> connections = {};

  //These are for manual testing without a heroku server

  @override
  dispose() {
    //To stop multiple calling websocket, use the following code.
    if (socket.disconnected) {
      socket.disconnect();
    }
    socket.disconnect();
    super.dispose();
  }

  @override
  void initState() {
    initRenderer();
    //print(widget.roomId);
    this.initSocket();
    super.initState();
  }

  void initSocket() {
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      "transports": ["websocket"],
      "autoConnect": false,
    });
    socket.connect();
    socket.on('connect', (_) {
      print('Connected id : ${socket.id}');
    });

    socket.onConnect((data) async {
      print('Socket Server Successfully connected');
      socket.emit("join", widget.roomId);
    });

    //Offer received from other client which is set as remote description and answer is created and transmitted
    socket.on("receiveOffer", (data) async {
      //print("Offer received");
      SocketId id = SocketId.fromJson(data["socketId"]);
      await _createConnection(id);
      String sdp = write(data["session"], null);

      RTCSessionDescription description = RTCSessionDescription(sdp, 'offer');

      await connections[id.destinationId]!
          .peer
          .setRemoteDescription(description);

      RTCSessionDescription description2 =
          await connections[id.destinationId]!.peer.createAnswer({
        //'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1
      }); // {'offerToReceiveVideo': 1 for video call

      var session = parse(description2.sdp.toString());

      connections[id.destinationId]!.peer.setLocalDescription(description2);
      socket
          .emit("createAnswer", {"session": session, "socketId": id.toJson()});
      setState(() {
        refresshVideoList = !refresshVideoList;
      });
    });
    //Answer received from originating client which is set as remote description
    socket.on("receiveAnswer", (data) async {
      //print("Answer received");
      String sdp = write(data["session"], null);

      RTCSessionDescription description = RTCSessionDescription(sdp, 'answer');

      await connections[data["socketId"]["destinationId"]]!
          .peer
          .setRemoteDescription(description);
      setState(() {
        refresshVideoList = !refresshVideoList;
      });
    });

    //Candidate received from answerer which is added to the peer connection
    //THIS COMPELETES THE CONNECTION PROCEDURE
    socket.on("receiveCandidate", (data) async {
      print("Candidate received");
      dynamic candidate = RTCIceCandidate(data['candidate']['candidate'],
          data['candidate']['sdpMid'], data['candidate']['sdpMlineIndex']);
      await connections[data['socketId']['destinationId']]!
          .peer
          .addCandidate(candidate);
    });

    socket.on("userDisconnected", (id) async {
      await connections[id]!.renderer.dispose();
      await connections[id]!.peer.close();
      connections.remove(id);
    });

    socket.onConnectError((data) {
      //print(data);
    });
  }

  Future<void> _createConnection(id) async {
    //print("Create connection");
    connections[id.destinationId] = Connection();
    connections[id.destinationId]!.renderer = RTCVideoRenderer();
    await connections[id.destinationId]!.renderer.initialize();
    connections[id.destinationId]!.peer =
        await createPeerConnection(configuration, offerSdpConstraints);
    connections[id.destinationId]!.peer.addStream(_localStream!);

    //The below onIceCandidate will not call if you are a caller
    connections[id.destinationId]!.peer.onIceCandidate = (e) {
      print("On-ICE Candidate is Finding");
      //Transmitting candidate data from answerer to caller
      if (e.candidate != null && !_offer) {
        socket.emit("sendCandidate", {
          "candidate": {
            'candidate': e.candidate.toString(),
            'sdpMid': e.sdpMid.toString(),
            'sdpMlineIndex': e.sdpMLineIndex,
          },
          "socketId": id.toJson(),
        });
      }
    };

    connections[id.destinationId]!.peer.onIceConnectionState = (e) {
      print(e);
    };

    connections[id.destinationId]!.peer.onAddStream = (stream) {
      //print('addStream: ' + stream.id);
      connections[id.destinationId]!.renderer.srcObject =
          stream; //same as the _remoteRenderer.srcObject = stream
    };
  }

  initRenderer() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize(); // for video call
    _localStream = await _getUserMedia();
  }

  //Get audio stream and save to local
  _getUserMedia() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      //'video': false,
      'video': {
        'facingMode': 'user',
      }, //If you want to make video calling app.
    };

    MediaStream stream = await navigator.mediaDevices.getUserMedia(constraints);

    _localRenderer.srcObject = stream;
    // _localRenderer.mirror = true;

    return stream;
  }

  Future<void> createOffer(id) async {
    RTCSessionDescription description =
        await connections[id.destinationId]!.peer.createOffer({
      //'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1
    }); //{'offerToReceiveVideo': 1} for video call
    var session = parse(description.sdp.toString());
    socket.emit("createOffer", {"session": session, "socketId": id.toJson()});
    setState(() {
      _offer = true;
    });

    connections[id.destinationId]!.peer.setLocalDescription(description);
  }

//This is the method that initiates the connection
  void _createOfferAndConnect() async {
    socket.emitWithAck("newConnect", widget.roomId, ack: (data) async {
      // print(
      //     "OriginId: ${data["originId"]}, DestinationIds: ${data["destinationIds"]}");

      data["destinationIds"].forEach((destinationId) async {
        if (connections[destinationId] == null) {
          SocketId id = SocketId(
              originId: data["originId"], destinationId: destinationId);
          await _createConnection(id);
          await createOffer(id);
        }
      });
      // await _createConnection(socketId);
      // await createOffer(socketId);
    });
  }

  //enable audio
  void _enableAudio() async {
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = true;
    });
  }

  //disable audio
  void _disableAudio() async {
    _localStream!.getAudioTracks().forEach((track) {
      track.enabled = false;
    });
  }

  // Codes for Video Call Grid
  List<Widget> renderStreamsGrid() {
    List<Widget> allRemoteVideo = [];

    connections.forEach((key, value) {
      allRemoteVideo.add(
        SizedBox(
          child: Container(
            width: 250,
            height: 200,
            color: Colors.yellow,
            child: RTCVideoView(
              value.renderer,
              // objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              // mirror: true,
            ),
          ),
        ),
      );

      //allRemoteVideo.add(value.renderer);
    });

    return allRemoteVideo;
  }

  @override
  Widget build(BuildContext context) {
    // return WillPopScope(
    //   onWillPop: () async {
    //     socket.disconnect();
    //     await _localRenderer.dispose();
    //     for (var key in connections.keys) {
    //       await connections[key]!.renderer.dispose();
    //       await connections[key]!.peer.close();
    //       connections.remove(key);
    //     }
    //     return true;
    //   },
    return Scaffold(
      appBar: AppBar(
        title: const Text("TALKMe"),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        child: Stack(
          children: [
            Container(
              //key: const Key("local"),
              width: double.infinity,
              height: double.infinity,
              color: Colors.blue,
              child: RTCVideoView(_localRenderer),
            ),
            Container(
              height: 300,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  shrinkWrap: true,
                  //itemCount: renderStreamsGrid().length,
                  itemCount: renderStreamsGrid().length,
                  itemBuilder: (context, index) {
                    return renderStreamsGrid()[index];
                  }),
            ),

            // Positioned(
            //   left: 10,
            //   bottom: 20,
            //   child: ListView.builder(
            //       scrollDirection: Axis.horizontal,
            //       shrinkWrap: true,
            //       itemCount: renderStreamsGrid().length,
            //       itemBuilder: (context, index) {
            //         return renderStreamsGrid()[index];
            //       }),
            // ),

            Positioned(
              width: 1199,
              height: 60,
              top: 20,
              left: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    //height: 50,
                    width: 200,
                    child: ElevatedButton(
                      onPressed: _createOfferAndConnect,
                      child: const Text('Connect'),
                    ),
                  ),
                  const SizedBox(
                    width: 50,
                  ),
                  SizedBox(
                      //height: 50,
                      width: 150,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_isAudioEnabled) {
                            _disableAudio();
                          } else {
                            _enableAudio();
                          }
                          setState(() {
                            _isAudioEnabled = !_isAudioEnabled;
                          });
                        },
                        child: Text(
                            'Mic is ${_isAudioEnabled == true ? "on" : "off"}'),
                      ))
                ],
              ),
            ),
          ],
        ),
        // const SizedBox(
        //   width: double.infinity,
        //   height: 40,
        // ),
      ),
    );
    //);
  }
}
