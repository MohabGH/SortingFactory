// Libraries

#include <Wire.h>    // I2C To connect PCA9685 To ESP32-S
#include <Adafruit_PWMServoDriver.h>  // To control Servo Motor through PCA9685
#include <BLEDevice.h>  // To turn on and name the Bluetooth BLE Chip in ESP32-S
#include <BLEServer.h>  // enable the ESP32-S as server so it can receive from the Mobile App
#include <BLEUtils.h>   // Helper Library to manage data and memory in BLE libraries
#include <BLE2902.h>    // Activate Descriptor (2902) needed for notifications and sending messages to Mobile App

// System Constants 

// Constants for PCA9685 to Control Servos

#define NUM_SERVO 6 // Number of used servo motors from 0 to 5 in PCA9685
#define SERVO_MIN_TICK 120 // assumed (for now) number of cycles to get "0" angle for servo motor
#define SERVO_MAX_TICK 510 // assumed (for now) number of cycles to get "180" angle for servo motor
#define SERVO_FREQ 50  // Standard Servo motor working frequency equivalent for a single pulse each 20ms
#define PCA9685_ADDR 0x40 // Default I2C address of the PCA9685 servo driver board

// Constants for BLE

#define BLE_DEVICE_NAME "SFRA_ESP"  // The name that will appear on the mobile while scaning for nearby bluetooth devices , The name stands for (Sorting Factory Robotic Arm ESP32-S)
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"  // Special ID Num for the connection service in ESP32-S
#define CHAR_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // the address of RX channel that mobile app will send data to ESP32 at
#define CHAR_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // the address of RX channel that ESP32 will send data to Mobile app at


// Constants for Timing for Servos , Bluetooth and etc

#define SERVO_STEP_INTERVAL 15 // the time between each change in servo motor movement for stable and smooth robotic arm movement (15ms)
#define LED_BLINK_INTERVAL 500 // the time between each blink for the Blue builtin_LED to determine Bluetooth Connection State (500ms)
#define BLE_ADV_DELAY 300      // Wait 300ms after BLE disconnect before restarting advertising

// Finite State Machine (FSM) States

// IN Manual Mode 

enum RobotState {
  STATE_WAIT_BLE = 0,  // Waiting State until the connection Between ESP32 and the mobile app becomes ready
  STATE_IDLE = 1,      // IDEL state after connection where everything is stopped until new commands received 
  STATE_PARSE_CMD = 2, // Messgae Recieved from mobile app and decision of which servo to move
  STATE_MOVING = 3,    // The State where the servo motors are actually moving until reaching the required angle
  STATE_FEEDBACK = 4   // The State where the mission completed and the ESP32 Send Confirmation Message to Mobile app before returning to the IDEL State
};


// PINOUT Definitions

#define STATUS_LED_PIN 2 // define for the BLUE BUILT_IN LED IN ESP32-S BOARD THAT are connected to GPIO2 to work as indication for Bluetooth State


// Hardware & BLE Objects

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver(PCA9685_ADDR); // create Object of the PCA9685 DRIVER library passing its I2C address (PCA9685_ADDR) and naming it "pwm"
BLEServer* pServer = NULL;  // Pointer that points to the place of Bluetooth Server in the memory
BLECharacteristic* pTxCharacteristic = NULL;   // Pointer that points to the place of Sending Channel in the memory

// Global Variables 

// Angles

int currentAngle[NUM_SERVO] = {90, 90, 90, 90, 90, 90};  // Array of integers  to store the current servo motor angle in it , initially (for now) each servo motor is at angle "90"
int targetAngle[NUM_SERVO]  = {90, 90, 90, 90, 90, 90};   // Array of integers  to store the required target servo motor angle that mobile app has sent

// States

RobotState currentState = STATE_WAIT_BLE;  // Stores the current State the Robotic arm in , initially the Robotic arm in the "0" STATE
volatile bool deviceConnected = false; // Added "volatile" so the Bluetooth connection state modified in background callbacks is safely read in loop()
bool ledState = LOW;  // To Store the current state of the Blue Builtin_LED (will be reversed each 500 ms)
bool pcaConnected = false; // Flag that stores whether the PCA9685 hardware is physically detected on I2C (true) or running in standalone simulation mode (false)

// Flags

volatile bool newCommandReceived = false; // Added "volatile" so the new message arrival flag is safely shared between BLE callbacks and loop()
String receivedCommand = "";   // a Variable that Stores the messages coming from the mobile app
bool pendingAdvertising = false; // Flag indicating we are waiting 300ms to restart BLE advertising after disconnect

// Timers

unsigned long lastServoMoveTime = 0;  // To Store the time by ms which happen in it that the servo did its last move
unsigned long lastLedBlinkTime = 0;   // To Store the time by ms which happen in it that the Blue Builtin_LED changed its state 
unsigned long disconnectTime = 0; // Stores the exact time in ms when BLE disconnected


// BLE Connection Callbacks (the Bluetooth working in the background without checking everytime and when something happen it call these functions)

class MyServerCallbacks : public BLEServerCallbacks {   // A class called MyServerCallbacks that inherits the Characteristics of server monitoring from the BLEServerCallbacks library and everypart of the code can see it as it is "Public"
  void onConnect(BLEServer* pServer) {  // get implemented immediately when the ESP32 connects to the mobile app 
    deviceConnected = true;  // then it changes the state BLUETOOTH connnection between the ESP32-S and Mobile to true
  }
  void onDisconnect(BLEServer* pServer) { // get implemented immediately when the connection between ESP32-S and Mobile get Disconnected
    deviceConnected = false;  // then it changes the state BLUETOOTH connnection between the ESP32-S and Mobile to false
  }
};


// BLE Data Receive Callbacks

class MyCallbacks : public BLECharacteristicCallbacks {   // A class called MyCallbacks that inherits the Characteristics of RX Channel monitoring from the BLECharacteristicCallbacks library and everypart of the code can see it as it is "Public"
  void onWrite(BLECharacteristic* pCharacteristic) {  // get implemented immediately when the mobile app send any message to ESP32-S
    String rxValue = pCharacteristic->getValue();  // getting the text recevied from the mobile app and temporary storing it in a Variables called "rxValue"
    
    rxValue.trim(); // Remove any leading/trailing spaces or newline characters (\r or \n) from the received BLE packet

    if (rxValue.length() > 0 && rxValue[0] >= 32 && rxValue[0] <= 126) { // Only accept non-empty printable ASCII text (ignores empty newlines or BLE handshake bytes)
      receivedCommand = rxValue;  // moving the recived message (from mobile app) from its temporary storage (rxValue) to its supposed general place "receivedCommand"
      newCommandReceived = true;  // changing the value of the indication of arrival of new message to true so the FSM Can Start its cycle
      Serial.print("Received from Mobile: "); // Print label on Serial Monitor before displaying the incoming command
      Serial.println(receivedCommand); // Print the exact command received from the mobile app on the Serial Monitor
    }
  }
};


// Function Prototypes (Declaration of functions Below the void loop)

int angleToPulse(int angle);
void setupPCA9685();
bool updateServoSmooth();
void setupBLE();
void sendBLEMessage(String message);
void updateStatusLED();
bool parseCommand(String cmd);


void setup() {
  Serial.begin(115200);  // To open the serial monitor on LAPTOP with speed of "115200" to follow up with the changes 
  pinMode(STATUS_LED_PIN, OUTPUT);   // To pinout the blue built_in LED as OUTPUT
  digitalWrite(STATUS_LED_PIN, LOW);  // When the ESP32-S start the led will be off

  setupPCA9685();  // To turn on The I2C and PCA9685 chip and Initializing all the servos at angle 90
  setupBLE();   // To turn on the BLUETOOTH and enable the ESP32-S to advertise itself in the bluetooth lists

  Serial.println("ESP32-S Ready, waiting for Bluetooth connection with the mobile");  // Initializig confirming message
}


void loop() {
  updateStatusLED();  // So the led is always indicates the Bluetooth connection State

  // Safety Guard: Reset State if Bluetooth Disconnects at any moment
  if (!deviceConnected && currentState != STATE_WAIT_BLE) {  // if The ESP32-S and mobile isn't connected and the Robot isn't in the waiting to connect state
    newCommandReceived = false;  // Remove any command 
    currentState = STATE_WAIT_BLE; // Return the Robot to the waiting to connect state
    disconnectTime = millis();     // Record the exact moment BLE disconnected
    pendingAdvertising = true;     // Raise flag to restart advertising after 300ms
    Serial.println("BLE Disconnected!!! , Returning to WAIT_BLE_STATE");  // Print message to follow up with the change appears in Serial Monitor
  }
     // 300ms wait before restarting BLE advertising
     if (pendingAdvertising && (millis() - disconnectTime >= BLE_ADV_DELAY)) {  // checking the 300 ms
      pendingAdvertising = false;    // Lower the flag so advertising starts only once
      BLEDevice::startAdvertising(); // Restart BLE advertising cleanly after 300ms
      Serial.println("BLE Advertising Restarted.");
     }
  

  switch (currentState) {    // To look at currentState Value then jump to the Case of this value

    // State 0: Waiting for the Mobile App Connection with ESP32-S
    case STATE_WAIT_BLE:   // if currentstate == STATE_WAIT_BLE 
      if (deviceConnected) {  // Check if ESP32-S Connected to the Mobile app
        newCommandReceived = false; // Clear any leftover command flag right when a new Bluetooth connection is established
        currentState = STATE_IDLE;  // if yes move to the next state
        Serial.println("BLE Connected , Entering IDLE State");   // Printing confirming message
      }
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // State 1: Connected & Waiting for New Command from mobile app
    case STATE_IDLE:   // if currentstate == STATE_WAIT_BLE
      if (newCommandReceived) {  // Since the Robot Becomes ready, it checks if there are any new commands
        newCommandReceived = false;  // yes? close the flag after you read it so the same message didn't get read twice
        currentState = STATE_PARSE_CMD;   // then move to the next state
      }
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // State 2: Check & Validate Incoming Command from mobile app
    case STATE_PARSE_CMD: {   // if currentstate == STATE_WAIT_BLE , The "{}" after the ":" because a new Variable "is vaild" has meaning in this case only
      bool isValid = parseCommand(receivedCommand);  // The message from mobile app get sent to "parsecommand" function and the return value get stored in a Variable called "isvaild"
      if (isValid) {  // checking the value of isvaild
        Serial.println("Valid Command -> Time to Move Servo Motors");  // true? means that the sent command was correct so we print a confirming message in the serial monitor
        sendBLEMessage("Moving..."); // Send immediate acknowledgment message to the mobile app confirming that servo movement has started
        currentState = STATE_MOVING;  // then move to the next state
      } else {  // is vaild was false? 
        Serial.print("Invalid Command Received: "); // Print invalid command warning prefix on Serial Monitor before printing the rejected text
        Serial.println(receivedCommand); // Print the exact rejected command text on Serial Monitor for debugging
        sendBLEMessage("ERROR, Try again");  // send a message to the user of the mobile app to let him know he wrote the wrong command
        currentState = STATE_IDLE;  // move backward to the IDLE State
      }
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
    }

    // State 3: Move Servo Motors Smoothly until Target Reached
    case STATE_MOVING: {   // if currentstate == STATE_MOVING , The "{}" after the ":" because a new Variable "reached" has meaning in this case only
      bool reached = updateServoSmooth();  // in each cycle "updateServoSmooth" function get called and stores its value in "reached" , as long as it's false, the servo motors move 1 angle degree each 15ms
      if (reached) {   // check the value of reached
        currentState = STATE_FEEDBACK;  // true? means all the servo motors reached to their target angle so move to the next state
      }
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
    }

    // State 4: Send Confirmation to Mobile App & Return to IDLE
    case STATE_FEEDBACK:  // if currentstate == STATE_FEEDBACK , note this is software code feedback not real feedback
      sendBLEMessage("DONE");  // sending a confirm "DONE" message to the mobile app
      Serial.println("Movement Complete -> Sent DONE");  // print a confirming message in the serial monitor that the Done message got sent to the mobile app
      currentState = STATE_IDLE;  // The Task is Done, return to the IDLE State
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // Fallback Safety Case
    default:  // a default state incase currentState took any wrong value out of its known values
      currentState = STATE_WAIT_BLE;  // return it to the 0 State
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
  }
}


// Controlling Servo Motors through 3 Functions


// Function 1: To Convert Angle (0-180) To PCA9685 Pulse Ticks (because PCA9685 doesn't understand normal servo angles, it only understands the language of "Pulses")
int angleToPulse(int angle) {  // This function returns integer value of the number of "TICKS" when it finishes , and it only needs to enter the required "angle" number as Parameter
  int safeAngle = constrain(angle, 0, 180); // it limits the value of the "safeAngle" between MIN number which is "0" and MAX number which is "180"  (if 200? > 180 ; if -10? > 0) to protect the servo from breaking its limits
  int pulse = map(safeAngle, 0, 180, SERVO_MIN_TICK, SERVO_MAX_TICK); // Linear Ratio and Proportion to change the angle range from the (0 to 180) range to TICKS range (150 to 600 (for now))
  return pulse; // Sends the final Tick Result to the spot the function got called in 
}


// Fucnction 2: Initialize PCA9685 Driver & Set Initial Positions
void setupPCA9685() {  // This function won't return any value 
  Wire.begin(21, 22);  // Turning on the I2C Connection and pinout it to GPIO21 (FOR SDA) and GPIO22 (FOR SCL)

  Wire.beginTransmission(PCA9685_ADDR); // Start an I2C test transmission to check if the PCA9685 chip responds at address 0x40
  if (Wire.endTransmission() == 0) { // If endTransmission() returns 0, the PCA9685 acknowledged and is physically wired
    pcaConnected = true; // Set flag to true so the code knows PCA9685 hardware is available
    pwm.begin();  // Turning on the PCA9685 To make it ready to recieve orders
    pwm.setPWMFreq(SERVO_FREQ); // Setting the Frequency of the out Pulses from the PCA9685 TO 50 HZ (THE VALUE OF THE CONSTANT NAMED SERVO_FREQ)

    for (int i = 0; i < NUM_SERVO; i++) {  // Repeat the Order for each of the 6 Servos
      int startPulse = angleToPulse(currentAngle[i]);  // Converting the angles of each servo starting from servo number "1" to number "6" to pulses 
      pwm.setPWM(i, 0, startPulse);  // This is the order which actually make the servo moves , it takes the number of the servo "i" and when to apply High (at the starting of the cycle) "0" and when to apply LOW at (the ending pulse of the cycle) "Start Pulse"
    }
    Serial.println("PCA9685 Connected & Initialized."); // Print confirmation on Serial Monitor that PCA9685 hardware was detected and initialized
  } else { // Runs if no PCA9685 device responded on the I2C bus
    pcaConnected = false; // Set flag to false so the ESP32-S skips I2C PWM calls and runs in simulation mode
    Serial.println("Note: PCA9685 not detected on I2C (Running in Simulation Mode)."); // Print notice on Serial Monitor that ESP32-S is running standalone without PCA9685 hardware
  }
}

// Function 3: Smooth Servo Movement
bool updateServoSmooth() {  // Returns either True or false depending on if the all the Servo Motors reached their promsied Spot or not
  if (millis() - lastServoMoveTime < SERVO_STEP_INTERVAL) {   // Equivalent to delay(15) but without stopping the ESP32-S or the code from flowing
    return false;
  }
  lastServoMoveTime = millis();  // if 15 ms really passed , we count another new 15 ms for the next movement
  bool allReached = true;  // initially assuming that all the servos reached their required spot

  for (int i = 0; i < NUM_SERVO; i++) {  // Repeat the Order for each of the 6 Servos
    if (currentAngle[i] < targetAngle[i]) {  // Checking if the current angle for each servo is less than the required or not
      currentAngle[i]++;  // if the current is less than the required, we increase the current angle by 1
      if (pcaConnected) { // Only send I2C PWM command if the PCA9685 board is actually connected
        pwm.setPWM(i, 0, angleToPulse(currentAngle[i]));  // Sending the new angle value to the Driver indicing that the servo still didn't finish its movement
      }
      allReached = false;  // The indicitor which tell that the Servos still didn't Finish Their Movement
    } else if (currentAngle[i] > targetAngle[i]) {  // if the current isn't less than the required, we Check if the current angle for each servo is less than the required or not
      currentAngle[i]--; // if the current is higher than the required, we reduce the current angle by 1
      if (pcaConnected) { // Only send I2C PWM command if the PCA9685 board is actually connected
        pwm.setPWM(i, 0, angleToPulse(currentAngle[i])); // Sending the new angle value to the Driver indicing that the servo still didn't finish its movement
      }
      allReached = false;  // The indicitor which tell that the Servos still didn't Finish Their Movement
    }
  }
  return allReached; // At the end if none of the motors moved which indicates (current angle = target angle) for all the Servos , we send "true" so FSM Cycle ends
}


// BLE , LED & Command Parser through 4 Functions

// Function 1: Initialize BLE Server, Service & Characteristics
void setupBLE() {  // Function for setup returns nothing
  BLEDevice::init(BLE_DEVICE_NAME); // To Turn on BLUETOOTH Chip in ESP32-S and give it a name (the one above in the constants "SFRA_ESP")

  pServer = BLEDevice::createServer();  // To create the Server
  pServer->setCallbacks(new MyServerCallbacks());  // To connect the server to our call backs class so it can detect when the connection get disconnected

  BLEService* pService = pServer->createService(SERVICE_UUID);  // To create the main service file inside the server and number it with the "SERVICE_UUID"

  pTxCharacteristic = pService->createCharacteristic(  // To create THE TX Channel to send data to the mobile app
    CHAR_TX_UUID, // Using the TX CHANNEL UUID 
    BLECharacteristic::PROPERTY_NOTIFY // Sending Notifications to the mobile app
  );
  BLE2902* p2902 = new BLE2902(); // Create an explicit instance of the standard 0x2902 CCCD Descriptor for BLE notifications
  p2902->setNotifications(true); // Explicitly enable notifications on the 0x2902 descriptor so mobile BLE apps reliably receive TX messages
  pTxCharacteristic->addDescriptor(p2902); // Attach the configured 0x2902 descriptor to the TX characteristic

  BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(  // To create THE TX Channel to recieve data from  the mobile app
    CHAR_RX_UUID,  // Using the RX CHANNEL UUID
    BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR   // making The RX Channel accept any type of writing either the normal or fast one without protocal so it can work with any mobile app 
  );
  pRxCharacteristic->setCallbacks(new MyCallbacks()); // To connect the RX channel to our call backs class so it can detect when the mobile app sends text and stores it

  pService->start();  // To Turn on the Service

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising(); // Get a pointer to the BLE Advertising object to configure scan response and connection intervals
  pAdvertising->addServiceUUID(SERVICE_UUID); // Add the main SERVICE_UUID to the BLE advertising packet via the pAdvertising pointer
  pAdvertising->setScanResponse(true); // Enable Scan Response so the full 128-bit SERVICE_UUID fits in the BLE broadcast packets
  pAdvertising->setMinPreferred(0x06); // Set preferred minimum connection interval (0x06 = 7.5ms) to improve connection stability with mobile phones
  BLEDevice::startAdvertising();  // start advertising the ESP32-S Board name (SFRA_ESP) so the mobile can access it in the Devices List to connect 
}

// Function 2: Send Feedback Message to Mobile App via BLE
void sendBLEMessage(String message) {  // Function for Sending message but returns nothing in the code
  if (deviceConnected && pTxCharacteristic != NULL) {  // we only send message when the ESP32-S is actually connected to the mobile and the TX Channel is ready
    String fullMsg = message + "\r\n"; // Append carriage return and newline (\r\n) so mobile terminal apps display each response on a separate clean line
    pTxCharacteristic->setValue(fullMsg.c_str()); // Convert "fullMsg" from String to C-string char array that the BLE library can send
    pTxCharacteristic->notify();  // Then it sends the message to the mobile app
  }
}

// Function 3: Non-Blocking Status LED Indicator
void updateStatusLED() {  // Function to change BLUE BUILT-IN LED STATE but returns nothing in the code
  if (deviceConnected) {  // checks if ESP32-S And Mobile app is connected 
    digitalWrite(STATUS_LED_PIN, HIGH); // yes? then the blue led will be on as long as connected
  } else {  // if  ESP32-S And Mobile app is not connected 
    if (millis() - lastLedBlinkTime >= LED_BLINK_INTERVAL) {  // eqiuvalent to delay(500) but without stopping the ESP32-S or the code
      lastLedBlinkTime = millis();  // if 500 ms really passed , we count another new 500 ms for the next blink
      ledState = !ledState;  // reverse the state of the led, if high make it low , if low make it high
      digitalWrite(STATUS_LED_PIN, ledState);  // apply the change on the led. so it gives the blinking effect
    }
  }
}

// Function 4: Parse Incoming Command for Servo Motors
bool parseCommand(String cmd) {  // Function to take the a copy of the text from mobile app and returns true incase of right command else returns false
  cmd.trim();  // To clean empty Spaces or new line signs
  if (cmd.length() == 0) {  // if the message was empty reject it 
    return false; // then return false
  }

  int tempTarget[NUM_SERVO];  // array of integers to temporary stores target angles for safety of servos incase of wrong angle command in one of the lastest servos in the message
  for (int i = 0; i < NUM_SERVO; i++) {  // Repeat the Order for each of the 6 Servos
    tempTarget[i] = targetAngle[i];  // if the whole message was correct we apply the changes in angle in the servos
  }

  int startIndex = 0;  // An indicator that starts at the first letter of the message from the mobile app that we will start cutting from
  while (startIndex < cmd.length()) {  // as long as the message didn't end continue the loop
    int commaIndex = cmd.indexOf(',', startIndex);  // To search for the spot of the first ',' starting from "startIndex" and returns the ',' spot
    String pair;  // Initializing a variable to remove certain pairs

    if (commaIndex == -1) {  // check if there are any ',' left 
      pair = cmd.substring(startIndex); // start cutting from "startIndex" to the end of the message and store it in "pair" 
      startIndex = cmd.length(); // moves the indicator to the first Index after the ','
    } else { // ',' detected 
      pair = cmd.substring(startIndex, commaIndex); // start cutting the text from "startIndex to before the ',' 
      startIndex = commaIndex + 1; // move the indicator to after the ','
    }

    pair.trim();  // remove any extra spaces after the ','
    int colonIndex = pair.indexOf(':'); // searching for the ':' in the pair
    if (colonIndex == -1) { // if not found 
      return false; // then wrong wording of the message
    }

    String servoStr = pair.substring(0, colonIndex); // Extract the substring before ":" representing the servo number as text
    String angleStr = pair.substring(colonIndex + 1); // Extract the substring after ":" representing the target angle as text
    servoStr.trim(); // Remove any extra spaces around the servo number text
    angleStr.trim(); // Remove any extra spaces around the angle value text

    if (servoStr.length() == 0 || angleStr.length() == 0) { // Reject the command if either the servo number or angle value is empty (e.g., ":90" or "0:")
      return false; // Return false because the pair is missing a value
    }

    for (unsigned int i = 0; i < servoStr.length(); i++) { // Loop through every character of servoStr to verify it contains only digits
      if (!isDigit(servoStr[i])) return false; // Reject immediately if a non-digit character is found (prevents "abc".toInt() from returning 0)
    }
    for (unsigned int i = 0; i < angleStr.length(); i++) { // new Loop through every character of angleStr to verify it contains only digits
      if (!isDigit(angleStr[i])) return false; // Reject immediately if a non-digit character is found
    }

    int servoIdx = servoStr.toInt(); // Convert the validated servo number text to an integer
    int angleVal = angleStr.toInt(); // Convert the validated angle value text to an integer

    if (servoIdx < 0 || servoIdx >= NUM_SERVO || angleVal < 0 || angleVal > 180) {  // checking that both has values within the right supposed range
      return false;
    }

    tempTarget[servoIdx] = angleVal;  // store the values temporary
  }

  for (int i = 0; i < NUM_SERVO; i++) {  // Repeat the Order for each of the 6 Servos
    targetAngle[i] = tempTarget[i];  // if the whole message was correct we apply the changes in angle in the servos
  }
  return true;  // reaching here means right command so we return true
}