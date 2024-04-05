import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const url = 'wss://api.kimhyun5u.com';

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.roomID});

  final String? roomID;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late WebSocketChannel channel;
  late RTCVideoRenderer _localRenderer;
  late RTCVideoRenderer _remoteRenderer;

  MediaStream? _localStream;
  RTCPeerConnection? pc;

  @override
  void initState() {
    super.initState();
    if (widget.roomID == null) {
      throw Exception('roomID is required');
    }
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _localRenderer.initialize();
    _remoteRenderer.initialize();

    connectSocket();
    joinRoom();
  }

  @override
  void dispose() {
    leave();

    _localRenderer.dispose();
    _remoteRenderer.dispose();

    channel.sink.close();

    super.dispose();
  }

  void leave() async {
    if (_localStream != null) {
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      await _localStream!.dispose();
      _localStream = null;
    }

    if (pc != null) {
      await pc!.close();
    }
  }

  void joinRoom() async {
    final config = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"},
        {
          "urls": "turn:api.kimhyun5u.com:3478",
          "username": "username1",
          "credential": "key1"
        }
      ]
    };

    final sdpConstraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional': []
    };

    final mediaConstraints = {
      'audio': false,
      'video': {'facingMode': 'user'}
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    pc = await createPeerConnection(config, sdpConstraints);

    _localRenderer.srcObject = _localStream;

    _localStream!.getTracks().forEach((track) {
      pc!.addTrack(track, _localStream!);
    });

    pc!.onIceCandidate = (ice) {
      onIceGenerated(ice);
    };

    pc!.onTrack = (event) {
      _remoteRenderer.srcObject = event.streams[0];
    };

    channel.sink.add(jsonEncode({'join': widget.roomID}));
  }

  void connectSocket() {
    log('연결요청!');
    channel = WebSocketChannel.connect(Uri.parse(url));
    initializeSocketListeners();
  }

  void initializeSocketListeners() {
    channel.stream.listen((data) {
      data = jsonDecode(data);

      if (data["joined"] == widget.roomID) {
        log(': socket--joined / $widget.roomID');
        onReceiveJoined();
      }
      if (data["offer"] != null) {
        log(': listener--offer');
        onReceiveOffer(data["offer"]);
      }
      if (data["answer"] != null) {
        log(' : socket--answer');
        onReceiveAnswer(data["answer"]);
      }
      if (data["ice"] != null) {
        log(': socket--ice');
        onReceiveIce(data["ice"]);
      }
    });
  }

  void onReceiveJoined() async {
    _sendOffer();
  }

  Future _sendOffer() async {
    log('send offer');

    RTCSessionDescription offer = await pc!.createOffer();
    pc!.setLocalDescription(offer);

    log(offer.toMap().toString());

    channel.sink.add(jsonEncode({'offer': offer.toMap()}));
  }

  Future<void> onReceiveOffer(data) async {
    final offer = RTCSessionDescription(data['sdp'], data['type']);
    pc!.setRemoteDescription(offer);

    final answer = await pc!.createAnswer();
    pc!.setLocalDescription(answer);

    _sendAnswer(answer);
  }

  Future _sendAnswer(answer) async {
    log(': send answer');
    channel.sink.add(jsonEncode({'answer': answer.toMap()}));
    log(answer.toMap().toString());
  }

  Future onReceiveAnswer(data) async {
    log('  --got answer');
    setState(() {});
    final answer = RTCSessionDescription(data['sdp'], data['type']);
    pc!.setRemoteDescription(answer);
  }

  Future onIceGenerated(RTCIceCandidate ice) async {
    log('send ice');
    setState(() {});

    channel.sink.add(jsonEncode({'ice': ice.toMap()}));

    log(ice.toMap().toString());
  }

  Future onReceiveIce(data) async {
    log('   --got ice');
    setState(() {});

    final ice = RTCIceCandidate(
      data['candidate'],
      data['sdpMid'],
      data['sdpMLineIndex'],
    );
    pc!.addCandidate(ice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${widget.roomID}'),
      ),
      body: Center(
          child: Row(
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: RTCVideoView(_localRenderer),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: RTCVideoView(_remoteRenderer),
            ),
          ),
        ],
      )),
    );
  }
}
