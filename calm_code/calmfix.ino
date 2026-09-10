#include <Wire.h>

#include "MAX30105.h"
#include "heartRate.h"

#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// =====================================================
// BLE
// =====================================================

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>


// =====================================================
// ESP32-C3 MINI PIN
// =====================================================

#define GSR_PIN 0

#define SDA_PIN 8
#define SCL_PIN 9


// =====================================================
// BLE UUID
// =====================================================

#define SERVICE_UUID \
  "12345678-1234-1234-1234-123456789001"

#define CHARACTERISTIC_UUID \
  "12345678-1234-1234-1234-123456789002"


// =====================================================
// BLE OBJECT
// =====================================================

BLECharacteristic *bleCharacteristic;

bool bleDeviceConnected = false;


// =====================================================
// RESET BASELINE FUNCTION
// =====================================================

void resetUserBaseline();


// =====================================================
// BLE SERVER CALLBACK
// =====================================================

class MyServerCallbacks : public BLEServerCallbacks {

  void onConnect(BLEServer *server) override {

    bleDeviceConnected = true;

    // ================================================
    // SETIAP CONNECTION = USER BARU
    // ================================================

    resetUserBaseline();

    Serial.println();
    Serial.println("======================================");
    Serial.println("         FLUTTER BLE CONNECTED");
    Serial.println("======================================");

    Serial.println("New user session detected.");
    Serial.println("GSR baseline will be recalculated.");
    Serial.println("BPM baseline will be recalculated.");
  }


  void onDisconnect(BLEServer *server) override {

    bleDeviceConnected = false;

    Serial.println();
    Serial.println("======================================");
    Serial.println("        FLUTTER BLE DISCONNECTED");
    Serial.println("======================================");

    delay(100);

    BLEDevice::startAdvertising();

    Serial.println("BLE advertising restarted.");
  }
};


// =====================================================
// SENSOR OBJECT
// =====================================================

MAX30105 maxSensor;
Adafruit_MPU6050 mpu;


// =====================================================
// SENSOR STATUS
// =====================================================

bool max30102OK = false;
bool mpu6050OK = false;


// =====================================================
// HEART RATE
// =====================================================

const byte RATE_SIZE = 4;

byte rates[RATE_SIZE];

byte rateSpot = 0;

byte validBeatCount = 0;

long lastBeat = 0;

float beatsPerMinute = 0;

int beatAvg = 0;


// =====================================================
// SENSOR DATA
// =====================================================

// GSR

int gsrValue = 0;

float gsrResistance = 0;

float gsrConductance = 0;

float gsrBaseline = 0;

float gsrRatio = 0;

bool gsrBaselineReady = false;

bool gsrHigh = false;


// =====================================================
// MAX30102
// =====================================================

long irValue = 0;

bool fingerDetected = false;


// =====================================================
// MPU6050 DATA
// =====================================================

float accX = 0;
float accY = 0;
float accZ = 0;

float gyroX = 0;
float gyroY = 0;
float gyroZ = 0;

float temperature = 0;


// =====================================================
// THRESHOLDS
// =====================================================

// BPM dianggap tinggi jika >= 120% BPM baseline

const float BPM_RATIO_THRESHOLD = 1.20;


// MAX30102 finger detection

const long IR_FINGER_THRESHOLD = 20000;


// MPU6050

const float ACC_MOTION_THRESHOLD = 1.5;

const float GYRO_MOTION_THRESHOLD = 0.5;


// GSR

const float GSR_RATIO_THRESHOLD = 2.0;


// =====================================================
// GSR CALIBRATION
// =====================================================

const float GSR_CALIBRATION = 512.0;


// =====================================================
// BASELINE SETTINGS
// =====================================================

const unsigned long BASELINE_DURATION = 10000;


// =====================================================
// TIMING
// =====================================================

const unsigned long GSR_INTERVAL = 20;

const unsigned long MAX_INTERVAL = 10;

const unsigned long MPU_INTERVAL = 20;

const unsigned long PRINT_INTERVAL = 500;

const unsigned long BLE_INTERVAL = 500;


unsigned long lastGSRTime = 0;

unsigned long lastMAXTime = 0;

unsigned long lastMPUTime = 0;

unsigned long lastPrintTime = 0;

unsigned long lastBLETime = 0;


// =====================================================
// GSR BASELINE VARIABLES
// =====================================================

unsigned long baselineStartTime = 0;

float baselineSum = 0;

unsigned long baselineSamples = 0;


// =====================================================
// BPM BASELINE VARIABLES
// =====================================================

unsigned long bpmBaselineStartTime = 0;

float bpmBaselineSum = 0;

unsigned long bpmBaselineSamples = 0;

float bpmBaseline = 0;

bool bpmBaselineReady = false;


// =====================================================
// MPU MOTION STATUS
// =====================================================

float accMagnitude = 0;

float gyroMagnitude = 0;

bool mpuMoving = false;


// =====================================================
// RESET USER BASELINE
// =====================================================

void resetUserBaseline() {

  // ===================================================
  // RESET GSR BASELINE
  // ===================================================

  gsrBaseline = 0;

  gsrRatio = 0;

  gsrHigh = false;

  gsrBaselineReady = false;

  baselineSum = 0;

  baselineSamples = 0;

  baselineStartTime = millis();


  // ===================================================
  // RESET BPM BASELINE
  // ===================================================

  bpmBaseline = 0;

  bpmBaselineReady = false;

  bpmBaselineSum = 0;

  bpmBaselineSamples = 0;

  bpmBaselineStartTime = 0;


  // ===================================================
  // RESET HEART RATE
  // ===================================================

  beatsPerMinute = 0;

  beatAvg = 0;

  lastBeat = 0;

  rateSpot = 0;

  validBeatCount = 0;


  for (byte i = 0; i < RATE_SIZE; i++) {

    rates[i] = 0;
  }


  // ===================================================
  // RESET SENSOR STATE
  // ===================================================

  fingerDetected = false;

  irValue = 0;

  gsrValue = 0;

  gsrResistance = 0;

  gsrConductance = 0;


  Serial.println();
  Serial.println("======================================");
  Serial.println("       USER BASELINE RESET");
  Serial.println("======================================");

  Serial.println("GSR baseline        : RESET");
  Serial.println("BPM baseline        : RESET");
  Serial.println("Heart rate average  : RESET");
  Serial.println("Beat history        : RESET");
  Serial.println("Baseline duration   : 10 seconds");

  Serial.println("======================================");
}


// =====================================================
// I2C SCANNER
// =====================================================

void i2cScanner() {

  Serial.println();
  Serial.println("======================================");
  Serial.println("          I2C SCANNER");
  Serial.println("======================================");

  byte count = 0;

  for (byte address = 1; address < 127; address++) {

    Wire.beginTransmission(address);

    byte error = Wire.endTransmission();

    if (error == 0) {

      Serial.print("I2C device found at 0x");

      if (address < 16) {
        Serial.print("0");
      }

      Serial.println(address, HEX);

      count++;
    }
  }

  Serial.println();

  if (count == 0) {

    Serial.println("NO I2C DEVICES FOUND!");

  } else {

    Serial.print("Total I2C devices: ");

    Serial.println(count);
  }

  Serial.println();
}


// =====================================================
// SETUP
// =====================================================

void setup() {

  Serial.begin(115200);

  delay(1500);


  // ===================================================
  // ADC
  // ===================================================

  analogReadResolution(10);


  // ===================================================
  // HEADER
  // ===================================================

  Serial.println();

  Serial.println("======================================");
  Serial.println("       CALM SENSOR MONITOR");
  Serial.println("          ESP32-C3 MINI");
  Serial.println("======================================");


  // ===================================================
  // I2C
  // ===================================================

  Serial.println();
  Serial.println("Initializing I2C...");

  Wire.begin(SDA_PIN, SCL_PIN);

  Serial.print("SDA = GPIO ");
  Serial.println(SDA_PIN);

  Serial.print("SCL = GPIO ");
  Serial.println(SCL_PIN);

  Serial.println("I2C initialized.");


  // ===================================================
  // I2C SCANNER
  // ===================================================

  i2cScanner();


  // ===================================================
  // MAX30102
  // ===================================================

  Serial.println("======================================");
  Serial.println("       INITIALIZING MAX30102");
  Serial.println("======================================");

  if (maxSensor.begin(Wire, I2C_SPEED_FAST)) {

    max30102OK = true;

    Serial.println("MAX30102 OK.");

    maxSensor.setup();

    maxSensor.setPulseAmplitudeRed(0x1F);

    maxSensor.setPulseAmplitudeIR(0x1F);

    maxSensor.setPulseAmplitudeGreen(0);

  }

  else {

    max30102OK = false;

    Serial.println("ERROR: MAX30102 NOT FOUND.");
  }


  // ===================================================
  // MPU6050
  // ===================================================

  Serial.println();

  Serial.println("======================================");
  Serial.println("       INITIALIZING MPU6050");
  Serial.println("======================================");

  if (mpu.begin(0x68, &Wire)) {

    mpu6050OK = true;

    Serial.println("MPU6050 OK.");

    mpu.setAccelerometerRange(
      MPU6050_RANGE_8_G
    );

    mpu.setGyroRange(
      MPU6050_RANGE_500_DEG
    );

    mpu.setFilterBandwidth(
      MPU6050_BAND_21_HZ
    );
  }

  else {

    mpu6050OK = false;

    Serial.println("ERROR: MPU6050 NOT FOUND.");
  }


  // ===================================================
  // GSR
  // ===================================================

  pinMode(GSR_PIN, INPUT);

  Serial.println();
  Serial.println("GSR : ANALOG INPUT READY");


  // ===================================================
  // BLE INITIALIZATION
  // ===================================================

  Serial.println();

  Serial.println("======================================");
  Serial.println("           INITIALIZING BLE");
  Serial.println("======================================");

  BLEDevice::init("CALM");

  BLEServer *server =
    BLEDevice::createServer();

  server->setCallbacks(
    new MyServerCallbacks()
  );


  BLEService *service =
    server->createService(
      SERVICE_UUID
    );


  bleCharacteristic =
    service->createCharacteristic(

      CHARACTERISTIC_UUID,

      BLECharacteristic::PROPERTY_READ |
      BLECharacteristic::PROPERTY_NOTIFY
    );


  bleCharacteristic->addDescriptor(
    new BLE2902()
  );


  bleCharacteristic->setValue(
    "CALM READY"
  );


  service->start();


  // ===================================================
  // BLE ADVERTISING
  // ===================================================

  BLEAdvertising *advertising =
    BLEDevice::getAdvertising();

  advertising->addServiceUUID(
    SERVICE_UUID
  );

  advertising->setScanResponse(true);

  BLEDevice::startAdvertising();


  Serial.println("BLE started.");

  Serial.println("Device name: CALM");

  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);

  Serial.print("Characteristic UUID: ");
  Serial.println(CHARACTERISTIC_UUID);

  Serial.println("Waiting for Flutter...");


  // ===================================================
  // FINAL SENSOR STATUS
  // ===================================================

  Serial.println();

  Serial.println("======================================");
  Serial.println("          SENSOR STATUS");
  Serial.println("======================================");

  Serial.print("MAX30102 : ");

  Serial.println(
    max30102OK ? "OK" : "FAILED"
  );


  Serial.print("MPU6050  : ");

  Serial.println(
    mpu6050OK ? "OK" : "FAILED"
  );


  Serial.println("GSR      : OK");

  Serial.println("BLE      : OK");

  Serial.println("======================================");


  // ===================================================
  // START GSR BASELINE
  // ===================================================

  Serial.println();

  Serial.println("======================================");
  Serial.println("       GSR BASELINE START");
  Serial.println("======================================");

  Serial.println("Pasang elektroda GSR.");

  Serial.println("Anak duduk tenang selama 10 detik.");

  baselineStartTime = millis();
}


// =====================================================
// READ GSR
// =====================================================

void readGSR() {

  gsrValue = analogRead(GSR_PIN);


  // ===================================================
  // ADC -> RESISTANCE
  // ===================================================

  float denominator =
    GSR_CALIBRATION - gsrValue;


  if (denominator > 0) {

    gsrResistance =

      (
        (1024.0 + (2.0 * gsrValue))
        * 10000.0
      )
      / denominator;


    // =================================================
    // RESISTANCE -> CONDUCTANCE
    // =================================================

    gsrConductance =

      (1.0 / gsrResistance)
      * 1000000.0;
  }

  else {

    gsrResistance = 0;

    gsrConductance = 0;
  }


  // ===================================================
  // GSR BASELINE
  // ===================================================

  if (!gsrBaselineReady) {

    if (
      gsrConductance > 0 &&
      gsrConductance < 1000
    ) {

      baselineSum += gsrConductance;

      baselineSamples++;
    }


    if (
      millis() - baselineStartTime
      >= BASELINE_DURATION
    ) {

      if (baselineSamples > 0) {

        gsrBaseline =
          baselineSum / baselineSamples;

        gsrBaselineReady = true;


        Serial.println();

        Serial.println(
          "======================================"
        );

        Serial.println(
          "       GSR BASELINE COMPLETE"
        );

        Serial.println(
          "======================================"
        );

        Serial.print("GSR Baseline : ");

        Serial.print(
          gsrBaseline,
          2
        );

        Serial.println(" uS");

        Serial.println(
          "GSR monitoring started."
        );

        Serial.println();
      }
    }

    return;
  }


  // ===================================================
  // GSR RATIO
  // ===================================================

  if (gsrBaseline > 0) {

    gsrRatio =
      gsrConductance / gsrBaseline;


    gsrHigh =
      gsrRatio >= GSR_RATIO_THRESHOLD;
  }
}


// =====================================================
// READ MAX30102
// =====================================================

void readMAX30102() {

  if (!max30102OK) {
    return;
  }


  // ===================================================
  // READ IR
  // ===================================================

  irValue =
    maxSensor.getIR();


  // ===================================================
  // FINGER DETECTION
  // ===================================================

  fingerDetected =
    irValue > IR_FINGER_THRESHOLD;


  // ===================================================
  // NO FINGER
  // ===================================================

  if (!fingerDetected) {

    beatsPerMinute = 0;

    beatAvg = 0;

    lastBeat = 0;

    rateSpot = 0;

    validBeatCount = 0;


    for (byte i = 0; i < RATE_SIZE; i++) {

      rates[i] = 0;
    }

    return;
  }


  // ===================================================
  // HEARTBEAT DETECTION
  // ===================================================

  if (checkForBeat(irValue)) {

    unsigned long currentBeatTime =
      millis();


    // =================================================
    // BEAT PERTAMA
    // =================================================

    if (lastBeat == 0) {

      lastBeat =
        currentBeatTime;

      return;
    }


    // =================================================
    // DELTA
    // =================================================

    long delta =
      currentBeatTime - lastBeat;


    lastBeat =
      currentBeatTime;


    // =================================================
    // VALID INTERVAL
    // =================================================

    if (
      delta > 250 &&
      delta < 3000
    ) {

      beatsPerMinute =

        60.0 /
        (delta / 1000.0);


      // =================================================
      // VALID BPM
      // =================================================

      if (
        beatsPerMinute >= 30 &&
        beatsPerMinute <= 220
      ) {

        rates[rateSpot] =
          (byte)beatsPerMinute;


        rateSpot++;

        rateSpot %= RATE_SIZE;


        // =================================================
        // JUMLAH DATA VALID
        // =================================================

        if (
          validBeatCount <
          RATE_SIZE
        ) {

          validBeatCount++;
        }


        // =================================================
        // AVERAGE
        // HANYA DATA VALID
        // =================================================

        int total = 0;


        for (
          byte i = 0;
          i < validBeatCount;
          i++
        ) {

          total += rates[i];
        }


        beatAvg =
          total / validBeatCount;
      }
    }
  }
}


// =====================================================
// UPDATE BPM BASELINE
// =====================================================

void updateBPMBaseline() {

  // ===================================================
  // BELUM ADA BPM VALID
  // ===================================================

  if (
    !max30102OK ||
    !fingerDetected ||
    beatAvg <= 0
  ) {

    return;
  }


  // ===================================================
  // MULAI TIMER BPM BASELINE
  // ===================================================

  if (
    bpmBaselineStartTime == 0
  ) {

    bpmBaselineStartTime =
      millis();


    Serial.println();

    Serial.println(
      "======================================"
    );

    Serial.println(
      "       BPM BASELINE START"
    );

    Serial.println(
      "======================================"
    );

    Serial.println(
      "Mengambil BPM baseline selama 10 detik."
    );
  }


  // ===================================================
  // COLLECT BPM
  // ===================================================

  if (!bpmBaselineReady) {

    bpmBaselineSum +=
      beatAvg;

    bpmBaselineSamples++;


    // =================================================
    // BASELINE COMPLETE
    // =================================================

    if (
      millis() -
      bpmBaselineStartTime
      >= BASELINE_DURATION
    ) {

      if (
        bpmBaselineSamples > 0
      ) {

        bpmBaseline =

          bpmBaselineSum /
          bpmBaselineSamples;


        bpmBaselineReady =
          true;


        Serial.println();

        Serial.println(
          "======================================"
        );

        Serial.println(
          "       BPM BASELINE COMPLETE"
        );

        Serial.println(
          "======================================"
        );


        Serial.print(
          "BPM Baseline : "
        );

        Serial.print(
          bpmBaseline,
          2
        );

        Serial.println(" BPM");


        Serial.print(
          "BPM Threshold : "
        );

        Serial.print(
          bpmBaseline *
          BPM_RATIO_THRESHOLD,
          2
        );

        Serial.println(" BPM");


        Serial.println(
          "BPM monitoring started."
        );

        Serial.println();
      }
    }
  }
}


// =====================================================
// READ MPU6050
// =====================================================

void readMPU6050() {

  if (!mpu6050OK) {
    return;
  }


  sensors_event_t acceleration;

  sensors_event_t gyro;

  sensors_event_t temp;


  mpu.getEvent(
    &acceleration,
    &gyro,
    &temp
  );


  // ===================================================
  // ACCELERATION
  // ===================================================

  accX =
    acceleration.acceleration.x;

  accY =
    acceleration.acceleration.y;

  accZ =
    acceleration.acceleration.z;


  // ===================================================
  // GYROSCOPE
  // ===================================================

  gyroX =
    gyro.gyro.x;

  gyroY =
    gyro.gyro.y;

  gyroZ =
    gyro.gyro.z;


  // ===================================================
  // TEMPERATURE
  // ===================================================

  temperature =
    temp.temperature;


  // ===================================================
  // MAGNITUDE
  // ===================================================

  accMagnitude =

    sqrt(

      accX * accX +
      accY * accY +
      accZ * accZ
    );


  gyroMagnitude =

    sqrt(

      gyroX * gyroX +
      gyroY * gyroY +
      gyroZ * gyroZ
    );


  // ===================================================
  // MOTION
  // ===================================================

  float accelerationDifference =

    fabs(
      accMagnitude - 9.81
    );


  if (

    accelerationDifference >
      ACC_MOTION_THRESHOLD

    ||

    gyroMagnitude >
      GYRO_MOTION_THRESHOLD

  ) {

    mpuMoving = true;
  }

  else {

    mpuMoving = false;
  }
}


// =====================================================
// GET STATUS DATA
// =====================================================

void getStatusData(

  bool &bpmHigh,

  bool &mpuCalm,

  bool &gsrCondition,

  int &conditionCount,

  const char* &status

) {

  // ===================================================
  // BPM
  // ===================================================

  bpmHigh = false;


  if (

    bpmBaselineReady &&

    fingerDetected &&

    beatAvg > 0 &&

    beatAvg >=
      (
        bpmBaseline *
        BPM_RATIO_THRESHOLD
      )

  ) {

    bpmHigh = true;
  }


  // ===================================================
  // MPU
  // ===================================================

  mpuCalm = false;


  if (

    mpu6050OK &&

    !mpuMoving

  ) {

    mpuCalm = true;
  }


  // ===================================================
  // GSR
  // ===================================================

  gsrCondition = false;


  if (

    gsrBaselineReady &&

    gsrHigh

  ) {

    gsrCondition = true;
  }


  // ===================================================
  // COUNT
  // ===================================================

  conditionCount = 0;


  if (bpmHigh) {
    conditionCount++;
  }


  if (mpuCalm) {
    conditionCount++;
  }


  if (gsrCondition) {
    conditionCount++;
  }


  // ===================================================
  // STATUS
  // ===================================================

  if (!gsrBaselineReady) {

    status = "BASELINE";
  }

  else if (conditionCount >= 3) {

    status = "MERAH";
  }

  else {

    status = "HIJAU";
  }
}


// =====================================================
// SEND BLE DATA
// =====================================================

void sendBLEData() {

  if (!bleDeviceConnected) {
    return;
  }


  // ===================================================
  // CONDITIONS
  // ===================================================

  bool bpmHigh;

  bool mpuCalm;

  bool gsrCondition;

  int conditionCount;

  const char* status;


  getStatusData(

    bpmHigh,

    mpuCalm,

    gsrCondition,

    conditionCount,

    status
  );


  // ===================================================
  // BPM OUTPUT
  // ===================================================

  int bpmOutput =
    beatAvg;


  if (
    !max30102OK ||
    !fingerDetected
  ) {

    bpmOutput = 0;
  }


  // ===================================================
  // CONDITION VALUES
  // ===================================================

  int bpmCondition =
    bpmHigh ? 1 : 0;


  int mpuCondition =
    mpuCalm ? 1 : 0;


  int gsrConditionOutput =
    gsrCondition ? 1 : 0;


  // ===================================================
  // CSV DATA
  // ===================================================

  String data =

    "DATA," +

    String(millis()) + "," +

    String(gsrValue) + "," +

    String(gsrConductance, 2) + "," +

    String(gsrBaseline, 2) + "," +

    String(bpmOutput) + "," +

    String(accMagnitude, 2) + "," +

    String(gyroMagnitude, 2) + "," +

    String(temperature, 2) + "," +

    String(bpmCondition) + "," +

    String(mpuCondition) + "," +

    String(gsrConditionOutput) + "," +

    String(conditionCount) + "," +

    String(status) +

    "\n";


  // ===================================================
  // BLE CHUNK
  // ===================================================
  // BLE default MTU aman menggunakan <= 20 byte.
  // Flutter akan menggabungkan kembali berdasarkan \n.
  // ===================================================

  const size_t CHUNK_SIZE = 20;


  for (
    size_t i = 0;
    i < data.length();
    i += CHUNK_SIZE
  ) {

    size_t end =
      i + CHUNK_SIZE;


    if (
      end >
      data.length()
    ) {

      end =
        data.length();
    }


    String chunk =
      data.substring(i, end);


    bleCharacteristic->setValue(
      (uint8_t*)chunk.c_str(),
      chunk.length()
    );


    bleCharacteristic->notify();


    delay(5);
  }


  // ===================================================
  // SERIAL DEBUG
  // ===================================================

  Serial.print("BLE DATA: ");

  Serial.print(data);
}


// =====================================================
// DETERMINE STATUS — SERIAL
// =====================================================

void determineStatus() {

  bool bpmHigh;

  bool mpuCalm;

  bool gsrCondition;

  int conditionCount;

  const char* status;


  getStatusData(

    bpmHigh,

    mpuCalm,

    gsrCondition,

    conditionCount,

    status
  );


  Serial.print("STATUS        : ");

  Serial.println(status);


  Serial.print("BPM condition : ");

  Serial.println(
    bpmHigh ? "YES" : "NO"
  );


  Serial.print("MPU calm      : ");

  Serial.println(
    mpuCalm ? "YES" : "NO"
  );


  Serial.print("GSR condition : ");

  Serial.println(
    gsrCondition ? "YES" : "NO"
  );


  Serial.print("Total         : ");

  Serial.print(conditionCount);

  Serial.println("/3");
}


// =====================================================
// PRINT DATA
// =====================================================

void printData() {

  Serial.println(
    "--------------------------------------"
  );


  // ===================================================
  // GSR
  // ===================================================

  Serial.print("GSR ADC       : ");

  Serial.println(gsrValue);


  if (gsrConductance > 0) {

    Serial.print(
      "GSR Resistance: "
    );

    Serial.print(
      gsrResistance / 1000.0,
      2
    );

    Serial.println(" kOhm");


    Serial.print(
      "GSR Conduct.  : "
    );

    Serial.print(
      gsrConductance,
      2
    );

    Serial.println(" uS");
  }


  if (gsrBaselineReady) {

    Serial.print(
      "GSR Baseline  : "
    );

    Serial.print(
      gsrBaseline,
      2
    );

    Serial.println(" uS");


    Serial.print(
      "GSR Ratio     : "
    );

    Serial.print(
      gsrRatio,
      2
    );

    Serial.println("x");


    Serial.print(
      "GSR >= 2x     : "
    );

    Serial.println(
      gsrHigh ? "YES" : "NO"
    );
  }

  else {

    Serial.println(
      "GSR Baseline  : CALIBRATING..."
    );
  }


  // ===================================================
  // MAX30102
  // ===================================================

  if (max30102OK) {

    Serial.print(
      "MAX30102 IR   : "
    );

    Serial.println(irValue);


    Serial.print(
      "Finger        : "
    );

    Serial.println(
      fingerDetected
        ? "DETECTED"
        : "NOT DETECTED"
    );


    if (fingerDetected) {

      Serial.print(
        "Heart Rate    : "
      );


      if (beatAvg > 0) {

        Serial.print(
          beatAvg
        );

        Serial.println(" BPM");


        if (bpmBaselineReady) {

          Serial.print(
            "BPM Baseline  : "
          );

          Serial.print(
            bpmBaseline,
            2
          );

          Serial.println(" BPM");


          Serial.print(
            "BPM Threshold : "
          );

          Serial.print(
            bpmBaseline *
            BPM_RATIO_THRESHOLD,
            2
          );

          Serial.println(" BPM");


          Serial.print(
            "BPM High      : "
          );


          Serial.println(

            (
              fingerDetected &&
              beatAvg > 0 &&
              beatAvg >=
                (
                  bpmBaseline *
                  BPM_RATIO_THRESHOLD
                )
            )

              ? "YES"
              : "NO"
          );
        }

        else {

          Serial.print(
            "BPM Baseline  : CALIBRATING..."
          );

          Serial.println();
        }
      }

      else {

        Serial.println(
          "Detecting..."
        );
      }
    }

    else {

      Serial.println(
        "Heart Rate    : No finger"
      );
    }
  }

  else {

    Serial.println(
      "MAX30102      : NOT AVAILABLE"
    );
  }


  // ===================================================
  // MPU6050
  // ===================================================

  if (mpu6050OK) {

    Serial.print(
      "Acceleration  : "
    );

    Serial.print(accX);

    Serial.print(" , ");

    Serial.print(accY);

    Serial.print(" , ");

    Serial.print(accZ);

    Serial.println(" m/s^2");


    Serial.print(
      "Accel Magnitude: "
    );

    Serial.print(
      accMagnitude,
      2
    );

    Serial.println(" m/s^2");


    Serial.print(
      "Gyroscope     : "
    );

    Serial.print(gyroX);

    Serial.print(" , ");

    Serial.print(gyroY);

    Serial.print(" , ");

    Serial.print(gyroZ);

    Serial.println(" rad/s");


    Serial.print(
      "Gyro Magnitude: "
    );

    Serial.print(
      gyroMagnitude,
      2
    );

    Serial.println(" rad/s");


    Serial.print(
      "MPU Movement  : "
    );

    Serial.println(
      mpuMoving
        ? "MOVING"
        : "CALM"
    );


    Serial.print(
      "Temperature   : "
    );

    Serial.print(
      temperature
    );

    Serial.println(" C");
  }

  else {

    Serial.println(
      "MPU6050       : NOT AVAILABLE"
    );
  }


  // ===================================================
  // FINAL STATUS
  // ===================================================

  Serial.println();


  if (gsrBaselineReady) {

    determineStatus();
  }

  else {

    Serial.println(
      "STATUS        : BASELINE..."
    );
  }


  Serial.println();
}


// =====================================================
// CSV DATA OUTPUT
// =====================================================

void printCSVData() {

  int bpmOutput =
    beatAvg;


  if (
    !max30102OK ||
    !fingerDetected
  ) {

    bpmOutput = 0;
  }


  bool bpmHigh;

  bool mpuCalm;

  bool gsrCondition;

  int conditionCount;

  const char* status;


  getStatusData(

    bpmHigh,

    mpuCalm,

    gsrCondition,

    conditionCount,

    status
  );


  int bpmCondition =
    bpmHigh ? 1 : 0;


  int mpuCondition =
    mpuCalm ? 1 : 0;


  int gsrConditionOutput =
    gsrCondition ? 1 : 0;


  // ===================================================
  // CSV
  // ===================================================

  Serial.print("DATA,");

  Serial.print(millis());

  Serial.print(",");

  Serial.print(gsrValue);

  Serial.print(",");

  Serial.print(
    gsrConductance,
    2
  );

  Serial.print(",");

  Serial.print(
    gsrBaseline,
    2
  );

  Serial.print(",");

  Serial.print(bpmOutput);

  Serial.print(",");

  Serial.print(
    accMagnitude,
    2
  );

  Serial.print(",");

  Serial.print(
    gyroMagnitude,
    2
  );

  Serial.print(",");

  Serial.print(
    temperature,
    2
  );

  Serial.print(",");

  Serial.print(bpmCondition);

  Serial.print(",");

  Serial.print(mpuCondition);

  Serial.print(",");

  Serial.print(
    gsrConditionOutput
  );

  Serial.print(",");

  Serial.print(conditionCount);

  Serial.print(",");

  Serial.println(status);
}


// =====================================================
// LOOP
// =====================================================

void loop() {

  unsigned long currentTime =
    millis();


  // ===================================================
  // GSR
  // ===================================================

  if (
    currentTime - lastGSRTime
    >= GSR_INTERVAL
  ) {

    lastGSRTime =
      currentTime;

    readGSR();
  }


  // ===================================================
  // MAX30102
  // ===================================================

  if (
    currentTime - lastMAXTime
    >= MAX_INTERVAL
  ) {

    lastMAXTime =
      currentTime;

    readMAX30102();
  }


  // ===================================================
  // BPM BASELINE
  // ===================================================

  updateBPMBaseline();


  // ===================================================
  // MPU6050
  // ===================================================

  if (
    currentTime - lastMPUTime
    >= MPU_INTERVAL
  ) {

    lastMPUTime =
      currentTime;

    readMPU6050();
  }


  // ===================================================
  // SERIAL PRINT
  // ===================================================

  if (
    currentTime - lastPrintTime
    >= PRINT_INTERVAL
  ) {

    lastPrintTime =
      currentTime;


    printData();


    // CSV untuk Python / Excel

    printCSVData();
  }


  // ===================================================
  // BLE
  // ===================================================

  if (
    currentTime - lastBLETime
    >= BLE_INTERVAL
  ) {

    lastBLETime =
      currentTime;


    sendBLEData();
  }
}