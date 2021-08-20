import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;

enum AudioFormat { raw, uLaw, mp3 }
enum AudioCh { ch1, ch2 }
enum AudioBit { bit8, bit16 }
enum AudioSampleRate { Hz8k, Hz16k }

class RubyDictationTemplate extends StatefulWidget {
  RubyDictationTemplate({Key? key}) : super(key: key);

  @override
  _RubyDictationTemplateState createState() => _RubyDictationTemplateState();
}

class _RubyDictationTemplateState extends State<RubyDictationTemplate> {
  late Uri webSocketUrl;
  late IOWebSocketChannel _channel;
  bool _connected = false;
  final List<String> msgs = <String>[""];
  AudioFormat? _audioFormat = AudioFormat.uLaw;
  AudioCh? _audioCh = AudioCh.ch2;
  AudioBit? _audioBit = AudioBit.bit8;
  AudioSampleRate? _audioSampleRate = AudioSampleRate.Hz8k;
  String _formatCommand = '';

  final _audioPath = ValueNotifier('');
  bool _audioExists = false;
  final _rubyDictationIP = ValueNotifier('');
  final _rubyDictationPort = ValueNotifier(0);
  String _webSocketUrl = '';
  List<bool> completeFlag = [false, false];

  final _audioPathController = TextEditingController();
  final _rubyDictationIPController = TextEditingController();
  final _rubyDictationPortController = TextEditingController();

  String getUrl() {
    var webSocketUrl = Uri(
        scheme: 'ws',
        host: _rubyDictationIP.value,
        port: _rubyDictationPort.value,
        pathSegments: [
          'RubyDictationService',
          'streamrecognition'
        ],
        queryParameters: {
          "x-rd-container-name": "Hitachi",
          "x-rd-user-id": "HitachiSolutionsTechnology",
          "x-rd-model-name": "ja_hst_hitachi",
        }).toString();

    setState(() => _webSocketUrl = webSocketUrl);
    return webSocketUrl;
  }

  void wsConnect() {
    _channel = IOWebSocketChannel.connect(getUrl(), headers: {
      "Connection": "keep-alive, Upgrade",
      "Pragma": "no-cache",
      "Cache-Control": "no-cache",
    });
    _channel.stream.listen((message) {
      setState(() => _connected = true);

      var json;

      try {
        json = jsonDecode(message);
      } catch (e, s) {
        print("Rudy Dictation String: $message");
        return;
      }

      String asrStatus = json["asr_status"];
      int ch = json["ch"];

      if (asrStatus == "final")
        for (var context in json['contexts']) {
          num start = context["sound_start_sec"];
          String text = context["text"];

          if (text != '') {
            print('start: $start, 話者: ${ch + 1}, $text');
            setState(() => msgs.add('start: $start, 話者: ${ch + 1}, $text'));
          }
        }
      else if (asrStatus == "complete") {
        if (json['contexts'][0]["text"] != '') {
          print('complete 話者: ${ch + 1} ${"-" * 20}');
          setState(() => msgs.add('complete 話者: ${ch + 1} ${"-" * 20}'));
        }

        for (var context in json['contexts']) {
          num start = context["sound_start_sec"];
          String text = context["text"];
          if (text != '') {
            print('start: $start, 話者: ${ch + 1}, $text');
            setState(() => msgs.add('start: $start, 話者: ${ch + 1}, $text'));
          }
        }
        completeFlag[ch] = true;

        if (json['contexts'][0]["text"] != '') {
          print('-' * 40);
          setState(() => msgs.add("-" * 40));
        }
      }

      if (completeFlag[0] && (completeFlag[1] || _audioCh == AudioCh.ch1)) {
        completeFlag = [false, false];
        if (msgs.length == 0) setState(() => msgs.add('テキストなし'));
        setState(() => msgs.add('音声認識完了'));
      }
    });
  }

  void wsCheckStatus() {
    wsConnect();
    _channel.sink.add('status');
  }

  String getFormatString() {
    var _temp = "format:";

    if (_audioFormat == AudioFormat.raw) {
      _temp += 'pcm:';
      if (_audioBit == AudioBit.bit8) {
        _temp += "8:";
      } else if (_audioBit == AudioBit.bit16) {
        _temp += "16:";
      }

      if (_audioSampleRate == AudioSampleRate.Hz8k) {
        _temp += "8000";
      } else if (_audioSampleRate == AudioSampleRate.Hz16k) {
        _temp += "16000";
      }
    } else if (_audioFormat == AudioFormat.uLaw) {
      _temp += "mulaw:8:8000";
    } else if (_audioFormat == AudioFormat.mp3) {
      _temp += "mp3:-1:-1";
    }

    if (_audioCh == AudioCh.ch1) {
      _temp += ":1";
    } else if (_audioCh == AudioCh.ch2) {
      _temp += ":2";
    }

    setState(() => _formatCommand = _temp);
    return _temp;
  }

  void wsFormat() {
    _channel.sink.add(_formatCommand);
  }

  void wsRecognize() {
    wsFormat();

    var myFile = File(_audioPath.value);
    var data = myFile.readAsBytesSync();

    setState(() => msgs.removeRange(0, msgs.length));

    _channel.sink.add(data);

    _channel.sink.add('complete');
  }

  void wsClose() {
    print("WebSocket close!");
    _channel.sink.close(status.goingAway);
  }

  @override
  void initState() {
    super.initState();

    _audioPath.addListener(() {
      setState(() => {_audioExists = File(_audioPath.value).existsSync()});
    });

    _rubyDictationIP.addListener(() {
      getUrl();
      setState(() => _connected = false);
    });

    _rubyDictationPort.addListener(() {
      getUrl();
      setState(() => _connected = false);
    });

    _rubyDictationIPController.text = '192.168.13.20';
    setState(() => _rubyDictationIP.value = _rubyDictationIPController.text);

    _rubyDictationPortController.text = '8302';
    setState(() => _rubyDictationPort.value =
        int.parse(_rubyDictationPortController.text));
  }

  @override
  void dispose() {
    wsClose();
    _audioPathController.dispose();
    _rubyDictationIPController.dispose();
    _rubyDictationPortController.dispose();
    _channel.sink.close();
    super.dispose();
  }

  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center,
        // crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration:
                BoxDecoration(border: Border.all(color: Colors.black12)),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Ruby Dictation',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: TextField(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'IP Address',
                    errorText:
                        _rubyDictationIPController.text != '' ? null : "必須です",
                    filled: true,
                  ),
                  controller: _rubyDictationIPController,
                  onChanged: (newValue) =>
                      {setState(() => _rubyDictationIP.value = newValue)},
                )),
                Container(
                    width: 100,
                    child: TextField(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Port',
                        hintText: "8302",
                        errorText: _rubyDictationPortController.text != ''
                            ? null
                            : "必須です",
                        filled: true,
                      ),
                      controller: _rubyDictationPortController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (newValue) => {
                        setState(() {
                          try {
                            _rubyDictationPort.value = int.parse(newValue);
                          } on FormatException catch (e, s) {}
                        })
                      },
                    )),
                // ElevatedButton(
                //     style: ElevatedButton.styleFrom(
                //         primary: Colors.green, fixedSize: Size(70, 55)),
                //     child: Text("Check"),
                //     onPressed: wsCheckStatus)
              ]),
            ),
          ),
          // Container(
          //     decoration: BoxDecoration(border: Border.all(color: Colors.black12)),
          //     child:
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: TextField(
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Audio file Path',
                  errorText: _audioExists ? null : "ファイルが存在しません",
                  filled: true,
                ),
                controller: _audioPathController,
                onChanged: (newValue) =>
                    {setState(() => _audioPath.value = newValue)},
              )),
              Align(
                  alignment: Alignment.topCenter,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          primary: Colors.green, fixedSize: Size(53, 53)),
                      child: Text("Select"),
                      onPressed: () async {
                        final typeGroup = XTypeGroup(
                            label: 'audio', extensions: ['wav', 'mp3']);
                        final file =
                            await openFile(acceptedTypeGroups: [typeGroup]);
                        if (file != null) {
                          setState(() => _audioPath.value = file.path);
                          _audioPathController.text = file.path;
                        }
                      }))
            ]),
          ),
          // )
          Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                  decoration:
                      BoxDecoration(border: Border.all(color: Colors.black12)),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                          child: ListTile(
                        title: const Text('Raw'),
                        leading: Radio<AudioFormat>(
                          value: AudioFormat.raw,
                          groupValue: _audioFormat,
                          onChanged: (AudioFormat? value) {
                            setState(() => _audioFormat = value);
                            getFormatString();
                          },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('μ-law'),
                        leading: Radio<AudioFormat>(
                          value: AudioFormat.uLaw,
                          groupValue: _audioFormat,
                          onChanged: (AudioFormat? value) {
                            setState(() => _audioFormat = value);
                            getFormatString();
                          },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('mp3'),
                        leading: Radio<AudioFormat>(
                          value: AudioFormat.mp3,
                          groupValue: _audioFormat,
                          onChanged: (AudioFormat? value) {
                            setState(() => _audioFormat = value);
                            getFormatString();
                          },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('1Ch'),
                        leading: Radio<AudioCh>(
                          activeColor: Colors.deepOrange,
                          value: AudioCh.ch1,
                          groupValue: _audioCh,
                          onChanged: (AudioCh? value) {
                            setState(() => _audioCh = value);
                            getFormatString();
                          },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('2Ch'),
                        leading: Radio<AudioCh>(
                          activeColor: Colors.deepOrange,
                          value: AudioCh.ch2,
                          groupValue: _audioCh,
                          onChanged: (AudioCh? value) {
                            setState(() => _audioCh = value);
                            getFormatString();
                          },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('8bit'),
                        leading: Radio<AudioBit>(
                          activeColor: Colors.green,
                          value: AudioBit.bit8,
                          groupValue: _audioBit,
                          onChanged: (_audioFormat == AudioFormat.uLaw ||
                                  _audioFormat == AudioFormat.mp3)
                              ? null
                              : (AudioBit? value) {
                                  setState(() => _audioBit = value);
                                  getFormatString();
                                },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('16bit'),
                        leading: Radio<AudioBit>(
                          activeColor: Colors.green,
                          value: AudioBit.bit16,
                          groupValue: _audioBit,
                          onChanged: (_audioFormat == AudioFormat.uLaw ||
                                  _audioFormat == AudioFormat.mp3)
                              ? null
                              : (AudioBit? value) {
                                  setState(() => _audioBit = value);
                                  getFormatString();
                                },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('8kHz'),
                        leading: Radio<AudioSampleRate>(
                          activeColor: Colors.amber,
                          value: AudioSampleRate.Hz8k,
                          groupValue: _audioSampleRate,
                          onChanged: (_audioFormat == AudioFormat.uLaw ||
                                  _audioFormat == AudioFormat.mp3)
                              ? null
                              : (AudioSampleRate? value) {
                                  setState(() => _audioSampleRate = value);
                                  getFormatString();
                                },
                        ),
                      )),
                      Expanded(
                          child: ListTile(
                        title: const Text('16kHz'),
                        leading: Radio<AudioSampleRate>(
                          activeColor: Colors.amber,
                          value: AudioSampleRate.Hz16k,
                          groupValue: _audioSampleRate,
                          onChanged: (_audioFormat == AudioFormat.uLaw ||
                                  _audioFormat == AudioFormat.mp3)
                              ? null
                              : (AudioSampleRate? value) {
                                  setState(() => _audioSampleRate = value);
                                  getFormatString();
                                },
                        ),
                      )),
                    ],
                  ))),
          Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                Expanded(
                    child: ElevatedButton(
                        child: Text("接続チェック"),
                        onPressed: !_connected ? wsCheckStatus : null)),
                Expanded(
                    child: ElevatedButton(
                        child: Text("Recognize"),
                        onPressed:
                            (_connected && _audioExists) ? wsRecognize : null)),
              ])),
          Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.black12)),
                child: Column(children: [
                  Row(children: [
                    Flexible(
                        child: Text(
                      _webSocketUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (_connected)
                      Icon(
                        Icons.check,
                        color: Colors.green,
                        size: 30.0,
                      )
                    else
                      Icon(
                        Icons.not_interested,
                        color: Colors.red,
                        size: 30.0,
                      )
                  ]),
                  Text(_formatCommand)
                ]),
              )),
          Padding(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                  decoration:
                      BoxDecoration(border: Border.all(color: Colors.black12)),
                  height: MediaQuery.of(context).size.height - 455,
                  child: ListView.builder(
                    itemCount: msgs.length,
                    itemBuilder: (context, index) {
                      return Text('${msgs[index]}');
                    },
                  ))),
        ]);
  }
}
