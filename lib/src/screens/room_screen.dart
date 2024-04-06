import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:frontend/src/utils/shoot_type.dart';
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
  String id = '';
  late ShootType _myShoot;
  bool _onFighting = false;
  bool _ready = false;
  final List<String> _countDown = ['start!', '가위', '바위', '보', 'stop!'];
  MediaStream? _localStream;
  RTCPeerConnection? pc;
  int _count = 0;
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

  // webrtc ----------------------------
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
    channel.stream.listen((data) async {
      data = jsonDecode(data);

      if (data["joined"] != null) {
        log(': socket--joined / $widget.roomID');
        id = data["joined"];
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
      if (_ready) {
        if (data['fight'] == 'ready') {
          log('fight ready');
        }
        if (data['fight'] == 'start') {
          log('fight start');
          setState(() {
            _onFighting = true;
          });

          for (var i = 0; i < _countDown.length; i++) {
            // count down 3, 2, 1 use future.delayed and setSTate
            await Future.delayed(const Duration(seconds: 1), () {
              setState(() {
                if (_count < _countDown.length - 1) {
                  _count++;
                }
              });
            });
          }

          // send my shoot
          channel.sink.add(jsonEncode({'shoot': _myShoot.index}));
        }
      }
      if (_onFighting) {
        if (data['result'] != null) {
          log('result: ${data['result']}');
          if (data['result'] == 'draw') {
            print('draw');
          } else {
            if (data['winner'] == id) {
              print('you win');
            } else {
              print('you lose');
            }
          }
          setState(() {
            _onFighting = false;
            _count = 0;
            _ready = false;
          });
        }
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

  // game ----------------------------
  void setReady() {
    setState(() {
      _ready = true;
    });

    if (!_onFighting) {
      channel.sink.add(jsonEncode({'fight': 'ready'}));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room ${widget.roomID}'),
      ),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
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
                ),
                !_onFighting
                    ? ElevatedButton(
                        onPressed: _ready
                            ? null
                            : () {
                                setReady();
                              },
                        child: const Text('Ready'),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: _onFighting
                                ? () {
                                    _myShoot = ShootType.rock;
                                  }
                                : null,
                            child: const Text('✊'),
                          ),
                          ElevatedButton(
                            onPressed: _onFighting
                                ? () {
                                    _myShoot = ShootType.scissors;
                                  }
                                : null,
                            child: const Text('✌️'),
                          ),
                          ElevatedButton(
                            onPressed: _onFighting
                                ? () {
                                    _myShoot = ShootType.paper;
                                  }
                                : null,
                            child: const Text('🖐️'),
                          ),
                        ],
                      ),
              ],
            ),
            _onFighting ? Text(_countDown[_count]) : Container(),
          ],
        ),
      ),
    );
  }
}
