import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// ============================================================
// CALM BLE UUID
// ============================================================

const String serviceUuid =
    "12345678-1234-1234-1234-123456789001";

const String characteristicUuid =
    "12345678-1234-1234-1234-123456789002";

// ============================================================
// COLORS
// ============================================================

const Color bgColor = Color(0xFF0B0F14);
const Color cardColor = Color(0xFF121820);
const Color cardColor2 = Color(0xFF171F29);

const Color primaryColor = Color(0xFF7C8CFF);

const Color greenColor = Color(0xFF4ADE80);
const Color yellowColor = Color(0xFFFACC15);
const Color redColor = Color(0xFFF87171);

const Color textPrimary = Color(0xFFF5F7FA);
const Color textSecondary = Color(0xFF8D98A7);

// ============================================================
// MAIN
// ============================================================

void main() {
  runApp(const CALMApp());
}

// ============================================================
// APP
// ============================================================

class CALMApp extends StatelessWidget {
  const CALMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CALM',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          surface: cardColor,
        ),
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const CALMHomePage(),
    );
  }
}

// ============================================================
// SENSOR DATA
// ============================================================

class SensorData {
  final int timestamp;

  final double gsrAdc;
  final double gsrConductance;
  final double gsrBaseline;

  final double bpm;

  final double accelMagnitude;
  final double gyroMagnitude;

  final double temperature;

  final bool bpmCondition;
  final bool mpuCondition;
  final bool gsrCondition;

  final int conditionCount;

  final String status;

  SensorData({
    required this.timestamp,
    required this.gsrAdc,
    required this.gsrConductance,
    required this.gsrBaseline,
    required this.bpm,
    required this.accelMagnitude,
    required this.gyroMagnitude,
    required this.temperature,
    required this.bpmCondition,
    required this.mpuCondition,
    required this.gsrCondition,
    required this.conditionCount,
    required this.status,
  });

  // ==========================================================
  // CSV PARSER
  // ==========================================================

  static SensorData? fromCsv(String line) {
    try {
      final parts = line.trim().split(',');

      if (parts.length < 14) {
        debugPrint(
          '⚠️ Invalid packet: ${parts.length} fields',
        );

        debugPrint(line);

        return null;
      }

      if (parts[0].trim().toUpperCase() != 'DATA') {
        return null;
      }

      bool parseBool(String value) {
        final v = value.trim().toLowerCase();

        return v == '1' ||
            v == 'true' ||
            v == 'yes';
      }

      return SensorData(
        timestamp:
            int.tryParse(parts[1].trim()) ?? 0,

        gsrAdc:
            double.tryParse(parts[2].trim()) ?? 0,

        gsrConductance:
            double.tryParse(parts[3].trim()) ?? 0,

        gsrBaseline:
            double.tryParse(parts[4].trim()) ?? 0,

        bpm:
            double.tryParse(parts[5].trim()) ?? 0,

        accelMagnitude:
            double.tryParse(parts[6].trim()) ?? 0,

        gyroMagnitude:
            double.tryParse(parts[7].trim()) ?? 0,

        temperature:
            double.tryParse(parts[8].trim()) ?? 0,

        bpmCondition:
            parseBool(parts[9]),

        mpuCondition:
            parseBool(parts[10]),

        gsrCondition:
            parseBool(parts[11]),

        conditionCount:
            int.tryParse(parts[12].trim()) ?? 0,

        status:
            parts.sublist(13).join(',').trim(),
      );
    } catch (e) {
      debugPrint(
        '❌ CSV parse error: $e',
      );

      return null;
    }
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class CALMHomePage extends StatefulWidget {
  const CALMHomePage({super.key});

  @override
  State<CALMHomePage> createState() =>
      _CALMHomePageState();
}

class _CALMHomePageState
    extends State<CALMHomePage> {

  // ==========================================================
  // BLE VARIABLES
  // ==========================================================

  BluetoothDevice? connectedDevice;

  BluetoothCharacteristic? dataCharacteristic;

  StreamSubscription<List<ScanResult>>?
      scanSubscription;

  StreamSubscription<BluetoothConnectionState>?
      connectionSubscription;

  StreamSubscription<List<int>>?
      notificationSubscription;

  bool isScanning = false;

  bool isConnecting = false;

  bool isConnected = false;

  String connectionMessage =
      'Not connected';

  // ==========================================================
  // SENSOR DATA
  // ==========================================================

  SensorData? latestData;

  final List<SensorData> history = [];

  String incomingBuffer = '';

  // ==========================================================
  // INIT
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _listenToBluetooth();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    scanSubscription?.cancel();

    connectionSubscription?.cancel();

    notificationSubscription?.cancel();

    super.dispose();
  }

  // ==========================================================
  // BLUETOOTH STATE
  // ==========================================================

  void _listenToBluetooth() {
    FlutterBluePlus.adapterState.listen(
      (state) {

        debugPrint(
          'Bluetooth state: $state',
        );

        if (!mounted) return;

        if (state != BluetoothAdapterState.on) {

          setState(() {
            connectionMessage =
                'Bluetooth is off';
          });

        } else if (!isConnected) {

          setState(() {
            connectionMessage =
                'Bluetooth ready';
          });
        }
      },
    );
  }

  // ==========================================================
  // SCAN
  // ==========================================================

  Future<void> startScan() async {

    if (isScanning ||
        isConnecting ||
        isConnected) {
      return;
    }

    try {

      final adapterState =
          await FlutterBluePlus.adapterState.first;

      if (adapterState !=
          BluetoothAdapterState.on) {

        _showMessage(
          'Turn on Bluetooth first.',
        );

        return;
      }

      setState(() {
        isScanning = true;
        connectionMessage =
            'Scanning for CALM...';
      });

      debugPrint('');
      debugPrint(
        '======================================',
      );
      debugPrint(
        '🔎 SCANNING FOR CALM',
      );
      debugPrint(
        '======================================',
      );

      await scanSubscription?.cancel();

      scanSubscription =
          FlutterBluePlus.scanResults.listen(
        (results) async {

          for (final result in results) {

            final device =
                result.device;

            final name =
                device.platformName.trim();

            final services =
                result.advertisementData.serviceUuids
                    .map(
                      (e) =>
                          e.toString().toLowerCase(),
                    )
                    .toList();

            final serviceMatch =
                services.contains(
              serviceUuid.toLowerCase(),
            );

            final nameMatch =
                name.toUpperCase() == 'CALM' ||
                name
                    .toUpperCase()
                    .contains('CALM');

            if (serviceMatch ||
                nameMatch) {

              debugPrint(
                '🎯 CALM FOUND',
              );

              debugPrint(
                'Name: $name',
              );

              debugPrint(
                'ID: ${device.remoteId}',
              );

              await FlutterBluePlus.stopScan();

              if (!mounted) return;

              setState(() {
                isScanning = false;
                connectionMessage =
                    'CALM found — connecting...';
              });

              await connectToDevice(device);

              return;
            }
          }
        },
      );

      await FlutterBluePlus.startScan(
        timeout:
            const Duration(seconds: 10),
      );

      await Future.delayed(
        const Duration(seconds: 10),
      );

      if (mounted &&
          !isConnected &&
          !isConnecting) {

        setState(() {
          isScanning = false;
          connectionMessage =
              'CALM device not found';
        });
      }

    } catch (e) {

      debugPrint(
        '❌ Scan error: $e',
      );

      if (mounted) {

        setState(() {
          isScanning = false;
          connectionMessage =
              'Scan failed';
        });
      }

      _showMessage(
        'BLE scan failed:\n$e',
      );
    }
  }

  // ==========================================================
  // CONNECT
  // ==========================================================

  Future<void> connectToDevice(
    BluetoothDevice device,
  ) async {

    if (isConnecting) return;

    isConnecting = true;

    try {

      debugPrint('');
      debugPrint(
        '======================================',
      );
      debugPrint(
        '🔗 CONNECTING TO CALM',
      );
      debugPrint(
        '======================================',
      );

      connectedDevice = device;

      await connectionSubscription?.cancel();

      await notificationSubscription?.cancel();

      connectionSubscription =
          device.connectionState.listen(
        (state) {

          debugPrint(
            '📡 Connection state: $state',
          );

          if (!mounted) return;

          if (state ==
              BluetoothConnectionState.connected) {

            setState(() {
              isConnected = true;
              connectionMessage =
                  'Connected';
            });

          } else if (
              state ==
                  BluetoothConnectionState
                      .disconnected) {

            setState(() {
              isConnected = false;
              connectionMessage =
                  'Disconnected';
            });

            dataCharacteristic = null;
          }
        },
      );

      // --------------------------------------------------------
      // CONNECT
      // --------------------------------------------------------

      try {

        await device.connect(
          timeout:
              const Duration(seconds: 15),
          license:
              License.nonprofit,
        );

      } catch (e) {

        debugPrint(
          '⚠️ Connect exception: $e',
        );

        final state =
            await device.connectionState.first;

        if (state !=
            BluetoothConnectionState.connected) {

          rethrow;
        }

        debugPrint(
          '✅ Device connected despite exception.',
        );
      }

      // --------------------------------------------------------
      // MTU
      // --------------------------------------------------------

      try {

        final mtu =
            await device.requestMtu(247);

        debugPrint(
          '📦 MTU: $mtu',
        );

      } catch (e) {

        debugPrint(
          '⚠️ MTU request failed: $e',
        );
      }

      // --------------------------------------------------------
      // DISCOVER SERVICES
      // --------------------------------------------------------

      if (mounted) {

        setState(() {
          isConnected = true;
          connectionMessage =
              'Discovering services...';
        });
      }

      await discoverAndSubscribe(
        device,
      );

    } catch (e) {

      debugPrint(
        '❌ Connection failed: $e',
      );

      if (mounted) {

        setState(() {
          isConnected = false;
          connectionMessage =
              'Connection failed';
        });
      }

      _showMessage(
        'Could not connect:\n$e',
      );

    } finally {

      isConnecting = false;
    }
  }

  // ==========================================================
  // DISCOVER + SUBSCRIBE
  // ==========================================================

  Future<void> discoverAndSubscribe(
    BluetoothDevice device,
  ) async {

    debugPrint('');
    debugPrint(
      '======================================',
    );
    debugPrint(
      '🔍 DISCOVERING SERVICES',
    );
    debugPrint(
      '======================================',
    );

    final services =
        await device.discoverServices();

    debugPrint(
      'Found ${services.length} services',
    );

    BluetoothService? calmService;

    BluetoothCharacteristic?
        calmCharacteristic;

    // ========================================================
    // PRINT ALL SERVICES
    // ========================================================

    for (final service in services) {

      final sid =
          service.uuid.toString().toLowerCase();

      debugPrint(
        'SERVICE: $sid',
      );

      for (
        final characteristic
        in service.characteristics
      ) {

        final cid =
            characteristic.uuid
                .toString()
                .toLowerCase();

        debugPrint(
          '  CHARACTERISTIC: $cid '
          'notify=${characteristic.properties.notify} '
          'indicate=${characteristic.properties.indicate} '
          'read=${characteristic.properties.read} '
          'write=${characteristic.properties.write}',
        );
      }
    }

    // ========================================================
    // FIND EXACT CALM SERVICE
    // ========================================================

    for (final service in services) {

      if (
        service.uuid
            .toString()
            .toLowerCase() ==
        serviceUuid.toLowerCase()
      ) {

        calmService = service;

        break;
      }
    }

    if (calmService == null) {

      debugPrint(
        '❌ CALM SERVICE NOT FOUND',
      );

      debugPrint(
        'Expected: $serviceUuid',
      );

      if (mounted) {

        setState(() {
          connectionMessage =
              'CALM service not found';
        });
      }

      _showMessage(
        'CALM service not found.\n\n'
        '$serviceUuid',
      );

      return;
    }

    debugPrint(
      '✅ CALM SERVICE FOUND',
    );

    // ========================================================
    // FIND EXACT CHARACTERISTIC
    // ========================================================

    for (
      final characteristic
      in calmService.characteristics
    ) {

      if (
        characteristic.uuid
            .toString()
            .toLowerCase() ==
        characteristicUuid.toLowerCase()
      ) {

        calmCharacteristic =
            characteristic;

        break;
      }
    }

    if (calmCharacteristic == null) {

      debugPrint(
        '❌ CALM DATA CHARACTERISTIC NOT FOUND',
      );

      debugPrint(
        'Expected: $characteristicUuid',
      );

      if (mounted) {

        setState(() {
          connectionMessage =
              'Data characteristic not found';
        });
      }

      _showMessage(
        'CALM data characteristic not found.\n\n'
        '$characteristicUuid',
      );

      return;
    }

    // ========================================================
    // VERIFY NOTIFICATION
    // ========================================================

    debugPrint('');
    debugPrint(
      '======================================',
    );
    debugPrint(
      '🎯 EXACT CALM CHARACTERISTIC',
    );
    debugPrint(
      '======================================',
    );

    debugPrint(
      'UUID: ${calmCharacteristic.uuid}',
    );

    debugPrint(
      'Notify: '
      '${calmCharacteristic.properties.notify}',
    );

    debugPrint(
      'Indicate: '
      '${calmCharacteristic.properties.indicate}',
    );

    debugPrint(
      '======================================',
    );

    if (
      !calmCharacteristic.properties.notify &&
      !calmCharacteristic.properties.indicate
    ) {

      _showMessage(
        'CALM characteristic does not support notification.',
      );

      return;
    }

    dataCharacteristic =
        calmCharacteristic;

    // ========================================================
    // ENABLE NOTIFICATION
    // ========================================================

    debugPrint(
      '🔔 Enabling notification...',
    );

    await calmCharacteristic.setNotifyValue(
      true,
    );

    debugPrint(
      '✅ NOTIFICATION ENABLED',
    );

    // ========================================================
    // LISTEN TO ONLY THIS CHARACTERISTIC
    // ========================================================

    await notificationSubscription?.cancel();

    notificationSubscription =
        calmCharacteristic.lastValueStream.listen(
      (value) {

        handleBleData(value);
      },

      onError: (error) {

        debugPrint(
          '❌ Notification error: $error',
        );
      },
    );

    if (mounted) {

      setState(() {
        isConnected = true;
        connectionMessage =
            'Connected • Live data';
      });
    }

    debugPrint('');
    debugPrint(
      '======================================',
    );
    debugPrint(
      '🎉 CALM LIVE DATA READY',
    );
    debugPrint(
      '======================================',
    );
  }

  // ==========================================================
  // HANDLE BLE BYTES
  // ==========================================================

  void handleBleData(
    List<int> bytes,
  ) {

    if (bytes.isEmpty) return;

    try {

      final chunk =
          utf8.decode(
        bytes,
        allowMalformed: true,
      );

      debugPrint(
        '📥 BLE RX: '
        '${chunk.replaceAll('\n', '\\n')}',
      );

      incomingBuffer += chunk;

      if (incomingBuffer.length > 10000) {

        debugPrint(
          '⚠️ BLE buffer reset.',
        );

        incomingBuffer = '';
      }

      while (
          incomingBuffer.contains('\n')) {

        final index =
            incomingBuffer.indexOf('\n');

        final line =
            incomingBuffer.substring(
          0,
          index,
        );

        incomingBuffer =
            incomingBuffer.substring(
          index + 1,
        );

        processLine(line);
      }

    } catch (e) {

      debugPrint(
        '❌ BLE decode error: $e',
      );
    }
  }

  // ==========================================================
  // PROCESS LINE
  // ==========================================================

  void processLine(
    String line,
  ) {

    final clean =
        line.trim();

    if (clean.isEmpty) return;

    debugPrint(
      '📄 LINE: $clean',
    );

    if (!clean.startsWith('DATA,')) {

      debugPrint(
        'ℹ️ Ignored:',
      );

      return;
    }

    final parsed =
        SensorData.fromCsv(clean);

    if (parsed == null) {

      debugPrint(
        '❌ Failed to parse DATA',
      );

      return;
    }

    debugPrint(
      '✅ DATA RECEIVED '
      'BPM=${parsed.bpm} '
      'GSR=${parsed.gsrConductance} '
      'ACC=${parsed.accelMagnitude} '
      'STATUS=${parsed.status}',
    );

    if (!mounted) return;

    setState(() {

      latestData = parsed;

      history.add(parsed);

      if (history.length > 120) {
        history.removeAt(0);
      }
    });
  }

  // ==========================================================
  // DISCONNECT
  // ==========================================================

  Future<void> disconnect() async {

    try {

      await notificationSubscription?.cancel();

      notificationSubscription = null;

      dataCharacteristic = null;

      await connectionSubscription?.cancel();

      connectionSubscription = null;

      if (connectedDevice != null) {

        await connectedDevice!.disconnect();
      }

    } catch (e) {

      debugPrint(
        'Disconnect error: $e',
      );
    }

    if (!mounted) return;

    setState(() {

      isConnected = false;

      connectedDevice = null;

      latestData = null;

      history.clear();

      incomingBuffer = '';

      connectionMessage =
          'Not connected';
    });
  }

  // ==========================================================
  // MESSAGE
  // ==========================================================

  void _showMessage(
    String message,
  ) {

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior:
              SnackBarBehavior.floating,
          backgroundColor:
              cardColor2,
        ),
      );
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    final data = latestData;

    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,

        titleSpacing: 20,

        title: Row(
          children: [

            Container(
              width: 42,
              height: 42,

              decoration: BoxDecoration(
                color: primaryColor
                    .withOpacity(0.15),

                borderRadius:
                    BorderRadius.circular(13),
              ),

              child: const Icon(
                Icons.favorite_rounded,
                color: primaryColor,
                size: 22,
              ),
            ),

            const SizedBox(width: 12),

            const Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Text(
                  'CALM',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),

                Text(
                  'Calming Autism Live Monitor',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),

        actions: [

          Padding(
            padding:
                const EdgeInsets.only(
              right: 18,
            ),

            child:
                _connectionIndicator(),
          ),
        ],
      ),

      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            8,
            20,
            35,
          ),

          children: [

            _buildConnectionCard(),

            const SizedBox(height: 18),

            _buildStatusCard(data),

            const SizedBox(height: 22),

            const Text(
              'Live Monitoring',
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 12),

            _buildHeartRateCard(data),

            const SizedBox(height: 12),

            Row(
              children: [

                Expanded(
                  child:
                      _buildSmallMetric(
                    icon:
                        Icons.water_drop_rounded,
                    title:
                        'Skin Conductance',
                    value:
                        data == null
                            ? '--'
                            : data.gsrConductance
                                .toStringAsFixed(2),
                    unit: 'µS',
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child:
                      _buildSmallMetric(
                    icon:
                        Icons.show_chart_rounded,
                    title:
                        'GSR Baseline',
                    value:
                        data == null
                            ? '--'
                            : data.gsrBaseline
                                .toStringAsFixed(2),
                    unit: 'µS',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            _buildSensorConditions(data),

            const SizedBox(height: 22),

            _buildMotionCard(data),

            const SizedBox(height: 22),

            _buildTemperatureCard(data),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // CONNECTION INDICATOR
  // ==========================================================

  Widget _connectionIndicator() {

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),

      decoration: BoxDecoration(
        color: isConnected
            ? greenColor.withOpacity(0.10)
            : Colors.white
                .withOpacity(0.05),

        borderRadius:
            BorderRadius.circular(20),
      ),

      child: Row(
        children: [

          Container(
            width: 7,
            height: 7,

            decoration:
                BoxDecoration(
              color: isConnected
                  ? greenColor
                  : textSecondary,

              shape: BoxShape.circle,
            ),
          ),

          const SizedBox(width: 6),

          Text(
            isConnected
                ? 'LIVE'
                : 'OFFLINE',

            style: TextStyle(
              color: isConnected
                  ? greenColor
                  : textSecondary,

              fontSize: 9,

              fontWeight:
                  FontWeight.w800,

              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONNECTION CARD
  // ==========================================================

  Widget _buildConnectionCard() {

    return Container(
      padding:
          const EdgeInsets.all(18),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Row(
        children: [

          Container(
            width: 46,
            height: 46,

            decoration: BoxDecoration(
              color:
                  primaryColor.withOpacity(
                0.12,
              ),

              borderRadius:
                  BorderRadius.circular(14),
            ),

            child: const Icon(
              Icons.bluetooth_rounded,
              color: primaryColor,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                const Text(
                  'CALM Device',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  connectionMessage,
                  style: const TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          if (!isConnected)

            ElevatedButton(
              onPressed:
                  isScanning ||
                          isConnecting
                      ? null
                      : startScan,

              style:
                  ElevatedButton.styleFrom(
                backgroundColor:
                    primaryColor,

                foregroundColor:
                    Colors.white,

                elevation: 0,

                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 11,
                ),

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              child: Text(
                isScanning
                    ? 'Scanning'
                    : 'Connect',

                style: const TextStyle(
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            )

          else

            OutlinedButton(
              onPressed: disconnect,

              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    textSecondary,

                side: BorderSide(
                  color: Colors.white
                      .withOpacity(0.10),
                ),

                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),

                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
              ),

              child: const Text(
                'Disconnect',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // STATUS CARD
  // ==========================================================

  Widget _buildStatusCard(
    SensorData? data,
  ) {

    final status =
        data?.status.toUpperCase() ??
            'WAITING';

    final info =
        _getStatusInfo(status);

    return Container(
      padding:
          const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(24),

        border: Border.all(
          color:
              info.color.withOpacity(0.18),
        ),

        boxShadow: [
          BoxShadow(
            color:
                info.color.withOpacity(
              0.04,
            ),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),

      child: Column(
        children: [

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,

            children: [

              Container(
                width: 8,
                height: 8,

                decoration:
                    BoxDecoration(
                  color: info.color,
                  shape: BoxShape.circle,
                ),
              ),

              const SizedBox(width: 8),

              Text(
                'CURRENT STATUS',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Text(
            status,

            style: TextStyle(
              color: info.color,
              fontSize: 40,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: -1.5,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            info.description,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: textSecondary,
              fontSize: 11,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 17),

          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 7,
            ),

            decoration: BoxDecoration(
              color:
                  info.color.withOpacity(
                0.08,
              ),

              borderRadius:
                  BorderRadius.circular(20),
            ),

            child: Text(
              data == null
                  ? 'Waiting for sensor data'
                  : '${data.conditionCount}/3 conditions',

              style: TextStyle(
                color: info.color,
                fontSize: 10,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // HEART RATE
  // ==========================================================

  Widget _buildHeartRateCard(
    SensorData? data,
  ) {

    final bpm =
        data?.bpm ?? 0;

    final high =
        data?.bpmCondition ?? false;

    return Container(
      padding:
          const EdgeInsets.all(20),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Row(
        children: [

          Container(
            width: 54,
            height: 54,

            decoration: BoxDecoration(
              color: high
                  ? redColor.withOpacity(
                      0.12,
                    )
                  : primaryColor.withOpacity(
                      0.12,
                    ),

              borderRadius:
                  BorderRadius.circular(16),
            ),

            child: Icon(
              Icons.favorite_rounded,

              color: high
                  ? redColor
                  : primaryColor,

              size: 26,
            ),
          ),

          const SizedBox(width: 15),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                const Text(
                  'Heart Rate',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 3),

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,

                  children: [

                    Text(
                      data == null ||
                              bpm == 0
                          ? '--'
                          : bpm.toStringAsFixed(
                              0,
                            ),

                      style: const TextStyle(
                        color: textPrimary,
                        fontSize: 31,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const SizedBox(width: 6),

                    const Padding(
                      padding:
                          EdgeInsets.only(
                        bottom: 5,
                      ),

                      child: Text(
                        'BPM',
                        style: TextStyle(
                          color:
                              textSecondary,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (high)
            _pill(
              'HIGH',
              redColor,
            )
          else if (
              data != null &&
              bpm > 0)
            _pill(
              'NORMAL',
              greenColor,
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // SMALL METRIC
  // ==========================================================

  Widget _buildSmallMetric({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
  }) {

    return Container(
      padding:
          const EdgeInsets.all(17),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(19),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          Icon(
            icon,
            color: primaryColor,
            size: 19,
          ),

          const SizedBox(height: 14),

          Text(
            value,

            style: const TextStyle(
              color: textPrimary,
              fontSize: 23,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(height: 2),

          Text(
            unit,

            style: const TextStyle(
              color: textSecondary,
              fontSize: 9,
              fontWeight:
                  FontWeight.w700,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            title,

            style: const TextStyle(
              color: textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CONDITIONS
  // ==========================================================

  Widget _buildSensorConditions(
    SensorData? data,
  ) {

    return Container(
      padding:
          const EdgeInsets.all(19),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(21),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          const Text(
            'Sensor Conditions',
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight:
                  FontWeight.w800,
            ),
          ),

          const SizedBox(height: 15),

          _conditionRow(
            icon:
                Icons.favorite_rounded,
            title:
                'Heart Rate',
            active:
                data?.bpmCondition ??
                    false,
            activeText:
                'HIGH',
            inactiveText:
                'NORMAL',
          ),

          _divider(),

          _conditionRow(
            icon:
                Icons.directions_run_rounded,
            title:
                'Movement',
            active:
                data != null &&
                !data.mpuCondition,
            activeText:
                'MOVING',
            inactiveText:
                'CALM',
          ),

          _divider(),

          _conditionRow(
            icon:
                Icons.water_drop_rounded,
            title:
                'GSR',
            active:
                data?.gsrCondition ??
                    false,
            activeText:
                'ELEVATED',
            inactiveText:
                'NORMAL',
          ),
        ],
      ),
    );
  }

  Widget _conditionRow({
    required IconData icon,
    required String title,
    required bool active,
    required String activeText,
    required String inactiveText,
  }) {

    return Row(
      children: [

        Container(
          width: 37,
          height: 37,

          decoration: BoxDecoration(
            color: active
                ? redColor.withOpacity(
                    0.10,
                  )
                : greenColor.withOpacity(
                    0.10,
                  ),

            borderRadius:
                BorderRadius.circular(11),
          ),

          child: Icon(
            icon,

            color: active
                ? redColor
                : greenColor,

            size: 18,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Text(
            title,

            style: const TextStyle(
              color: textPrimary,
              fontSize: 12,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ),

        _pill(
          active
              ? activeText
              : inactiveText,

          active
              ? redColor
              : greenColor,
        ),
      ],
    );
  }

  Widget _divider() {

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 13,
      ),

      child: Divider(
        height: 1,
        color:
            Colors.white.withOpacity(0.05),
      ),
    );
  }

  // ==========================================================
  // MOTION
  // ==========================================================

  Widget _buildMotionCard(
    SensorData? data,
  ) {

    return Container(
      padding:
          const EdgeInsets.all(19),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(21),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          const Row(
            children: [

              Icon(
                Icons.sensors_rounded,
                color: primaryColor,
                size: 19,
              ),

              SizedBox(width: 8),

              Text(
                'Motion Monitoring',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            children: [

              Expanded(
                child:
                    _motionValue(
                  'Acceleration',
                  data?.accelMagnitude ??
                      0,
                  'm/s²',
                ),
              ),

              Container(
                width: 1,
                height: 45,
                color:
                    Colors.white.withOpacity(
                  0.06,
                ),
              ),

              Expanded(
                child:
                    _motionValue(
                  'Gyroscope',
                  data?.gyroMagnitude ??
                      0,
                  'rad/s',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _motionValue(
    String title,
    double value,
    String unit,
  ) {

    return Column(
      children: [

        Text(
          value == 0
              ? '--'
              : value.toStringAsFixed(2),

          style: const TextStyle(
            color: textPrimary,
            fontSize: 22,
            fontWeight:
                FontWeight.w900,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          unit,

          style: const TextStyle(
            color: textSecondary,
            fontSize: 9,
            fontWeight:
                FontWeight.w700,
          ),
        ),

        const SizedBox(height: 4),

        Text(
          title,

          style: const TextStyle(
            color: textSecondary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // TEMPERATURE
  // ==========================================================

  Widget _buildTemperatureCard(
    SensorData? data,
  ) {

    return Container(
      padding:
          const EdgeInsets.all(19),

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(21),

        border: Border.all(
          color:
              Colors.white.withOpacity(0.06),
        ),
      ),

      child: Row(
        children: [

          Container(
            width: 42,
            height: 42,

            decoration: BoxDecoration(
              color:
                  primaryColor.withOpacity(
                0.10,
              ),

              borderRadius:
                  BorderRadius.circular(13),
            ),

            child: const Icon(
              Icons.thermostat_rounded,
              color: primaryColor,
              size: 21,
            ),
          ),

          const SizedBox(width: 13),

          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,

              children: [

                Text(
                  'Temperature',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 10,
                  ),
                ),

                SizedBox(height: 3),

                Text(
                  'Sensor temperature',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Text(
            data == null
                ? '--'
                : '${data.temperature.toStringAsFixed(1)} °C',

            style: const TextStyle(
              color: textPrimary,
              fontSize: 20,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PILL
  // ==========================================================

  Widget _pill(
    String text,
    Color color,
  ) {

    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),

      decoration: BoxDecoration(
        color:
            color.withOpacity(0.10),

        borderRadius:
            BorderRadius.circular(10),
      ),

      child: Text(
        text,

        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight:
              FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ==========================================================
  // STATUS INFO
  // ==========================================================

  _StatusInfo _getStatusInfo(
    String status,
  ) {

    switch (status) {

      case 'MERAH':

        return _StatusInfo(
          color: redColor,

          description:
              'Multiple monitored indicators are elevated.',
        );

      case 'KUNING':

        return _StatusInfo(
          color: yellowColor,

          description:
              'Some indicators require closer monitoring.',
        );

      case 'HIJAU':

        return _StatusInfo(
          color: greenColor,

          description:
              'Current monitored indicators are within the expected range.',
        );

      case 'BASELINE':

        return _StatusInfo(
          color: primaryColor,

          description:
              'CALM is collecting baseline measurements.',
        );

      default:

        return _StatusInfo(
          color: textSecondary,

          description:
              'Connect the CALM device to begin monitoring.',
        );
    }
  }
}

// ============================================================
// STATUS INFO CLASS
// ============================================================

class _StatusInfo {

  final Color color;

  final String description;

  _StatusInfo({
    required this.color,
    required this.description,
  });
}