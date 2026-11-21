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
#define SERVO_MIN_TICK 120 // assumed number of cycles to get "0" angle for servo motor
#define SERVO_MAX_TICK 510 // assumed number of cycles to get "180" angle for servo motor
#define SERVO_FREQ 50  // Standard Servo motor working frequency equivalent for a single pulse each 20ms
#define PCA9685_ADDR 0x40 // Default I2C address of the PCA9685 servo driver board

// Constants for BLE

#define BLE_DEVICE_NAME "SFRA_ESP"  // The name that will appear on the mobile while scaning for nearby bluetooth devices , The name stands for (Sorting Factory Robotic Arm ESP32-S)
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"  // Special ID Num for the connection service in ESP32-S
#define CHAR_RX_UUID "6E400002-B5A3-F393-E0A9-E50E24DCCA9E" // the address of RX channel that mobile app will send data to ESP32 at
#define CHAR_TX_UUID "6E400003-B5A3-F393-E0A9-E50E24DCCA9E" // the address of RX channel that ESP32 will send data to Mobile app at


// Constants for Timing for Servos , Bluetooth and etc

#define SERVO_STEP_INTERVAL 50 // the time between each change in servo motor movement for stable and smooth robotic arm movement (15ms)
#define SERVO_WAKEUP_INTERVAL 250  // 250ms interval between energizing each servo at startup
#define LED_BLINK_INTERVAL 500 // the time between each blink for the Blue builtin_LED to determine Bluetooth Connection State (500ms)
#define BLE_ADV_DELAY 300      // Wait 300ms after BLE disconnect before restarting advertising
#define EMERGENCY_TIMEOUT_MS 60000 // Wait 1 minute (60,000ms) in Emergency State before auto-returning HOME


// Assumed Robotic Arm Angles (for now) 
// Joint Order: [0]=Base, [1]=Shoulder, [2]Elbow, [3]Wrist_Pitch, [4]Wrist_Roll, [5]Gripper

#define GRIPPER_OPEN_ANGLE 30 // Assumed angle where the gripper fingers are open
#define GRIPPER_CLOSE_ANGLE 110 // Assumed angle where the gripper fingers are Close
#define LIFT_SHOULDER_ANGLE 105 // Assumed safe lifted shoulder angle to clear the platform and bin walls
#define LIFT_ELBOW_ANGLE 85    // Assumed safe lifted elbow angle during transport

// Target Angles above the 3 Inline Sorting Bins (Base + Reach adjusted for Near, Middle, Far bins)
const int BIN1_ANGLES[NUM_SERVO] = {55, 80, 105, 90, 90, GRIPPER_CLOSE_ANGLE}; // Bin 1: Red (R) | Square (S) | Paper (P)
const int BIN2_ANGLES[NUM_SERVO] = {35, 70, 115, 90, 90, GRIPPER_CLOSE_ANGLE}; // Bin 2: Blue (B) | Triangle (T) | Plastic (L)
const int BIN3_ANGLES[NUM_SERVO] = {15, 60, 125, 90, 90, GRIPPER_CLOSE_ANGLE}; // Bin 3: Green (G) | Circle (C) | Glass (Z)

// Finite State Machine (FSM) States


// High-Level System Operating Modes (Controlled by Mobile App Menu)

enum SystemMode {
  MODE_STANDBY = 0,     // Initial state after BLE connect, waiting for 'M' (Manual) or 'A' (Auto later)
  MODE_MANUAL_MENU = 1, // Entered Manual Mode ('M'), waiting to choose Sub-Mode ('1' Arm Control or '2' Manual Sort)
  MODE_ARM_CONTROL = 2, // Sub-Mode 1: Direct joint angle control (e.g., "0:90,2:45")
  MODE_MANUAL_SORT = 3  // Sub-Mode 2: 3-Bin sorting via single-letter commands (R,B,G / S,T,C / P,L,Z)
};

// IN Manual Mode 

// Manual Arm Control 

enum RobotState {
  STATE_INIT_SERVOS = 0, // sequential wakeup of the 6 servos at startup 
  STATE_WAIT_BLE = 1,    // Waiting State until the connection Between ESP32 and the mobile app becomes ready
  STATE_IDLE = 2,        // IDLE state after connection where everything is stopped until new commands received
  STATE_PARSE_CMD = 3,   // Message Received from mobile app and decision (Manual Move, Sorting Bin, or Home)
  STATE_MOVING = 4,      // The State where the servo motors are moving smoothly (single move or multi-step sorting)
  STATE_FEEDBACK = 5,    // The State where the mission completed and the ESP32 sends DONE / SORT_DONE to Mobile App
  STATE_EMERGENCY = 6    // Locked Emergency State: freezes arm for 1 min unless "CLEAR EMERGENCY" is received
};

// Manual Sorting

enum SortStep {
  SORT_NONE = 0,        // Not in a sorting sequence (normal manual joint move or HOME command)
  SORT_GRAB = 1,        // Step 1: Close gripper on the object resting on the blue pick platform
  SORT_LIFT = 2,        // Step 2: Lift arm slightly upward so the object clears obstacles
  SORT_TO_BIN = 3,      // Step 3: Rotate base and reach above the selected sorting bin (Bin 1, 2, or 3)
  SORT_RELEASE = 4,     // Step 4: Open gripper to drop the object into the bin
  SORT_RETURN_HOME = 5  // Step 5: Return arm back to HOME_ANGLES above the blue pick platform
};


// PINOUT Definitions

#define STATUS_LED_PIN 2 // define for the BLUE BUILT_IN LED IN ESP32-S BOARD THAT are connected to GPIO2 to work as indication for Bluetooth State


// Hardware & BLE Objects

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver(PCA9685_ADDR); // create Object of the PCA9685 DRIVER library passing its I2C address (PCA9685_ADDR) and naming it "pwm"
BLEServer* pServer = NULL;  // Pointer that points to the place of Bluetooth Server in the memory
BLECharacteristic* pTxCharacteristic = NULL;   // Pointer that points to the place of Sending Channel in the memory

// Global Variables 

// Angles
int currentAngle[NUM_SERVO] = {90, 75, 110, 90, 90, GRIPPER_OPEN_ANGLE}; // Starts at safe HOME posture
int targetAngle[NUM_SERVO]  = {90, 75, 110, 90, 90, GRIPPER_OPEN_ANGLE}; // Matches initial safe HOME posture
const int HOME_ANGLES[NUM_SERVO] = {90, 75, 110, 90, 90, 30};    // Default Safe Home / Ready Angles (Close to Pick Platform, Gripper Open) - Assumed values until assembly
int activeBinAngles[NUM_SERVO]; // Temporary array storing the target angles of the currently selected bin (Bin 1, 2, or 3)
int savedTargetAngle[NUM_SERVO]; // Backup array storing the interrupted target angles so "CLEAR EMERGENCY" can resume smoothly

// States
SystemMode currentMode = MODE_STANDBY; // Tracks which screen/mode the mobile app is currently operating in
RobotState currentState = STATE_INIT_SERVOS; // Starts in STATE_INIT_SERVOS to wake up servos safely one-by-one before BLE
SortStep currentSortStep = SORT_NONE;        // Tracks which step of the 5-step sorting sequence is currently running
volatile bool deviceConnected = false;       // Added "volatile" so the Bluetooth connection state modified in background callbacks is safely read in loop()
bool ledState = LOW;                         // To Store the current state of the Blue Builtin_LED (will be reversed each 500 ms)
bool pcaConnected = false;                   // Flag that stores whether the PCA9685 hardware is physically detected on I2C (true) or running in simulation mode (false)
int wakeupServoIndex = 0;                    // Counter (0 to 5) tracking which servo is being energized next during STATE_INIT_SERVOS

// Flags
volatile bool newCommandReceived = false;  // Added "volatile" so the new message arrival flag is safely shared between BLE callbacks and loop()
volatile bool emergencyStopFlag = false;   // Priority flag raised immediately if mobile sends 'E' or 'STOP' during motion
String receivedCommand = "";               // a Variable that Stores the messages coming from the mobile app
bool pendingAdvertising = false;           // Flag indicating we are waiting 300ms to restart BLE advertising after disconnect
volatile bool clearEmergencyFlag = false; // Priority flag raised when mobile sends "CLEAR EMERGENCY" during the 1-min window
bool isSortingTask = false;               // True when executing a 5-step sorting cycle, false for single manual moves

// Timers
unsigned long lastServoMoveTime = 0;   // To Store the time by ms which happen in it that the servo did its last move
unsigned long lastServoWakeupTime = 0; // To Store the time by ms of the last servo wakeup during startup
unsigned long lastLedBlinkTime = 0;    // To Store the time by ms which happen in it that the Blue Builtin_LED changed its state 
unsigned long disconnectTime = 0;      // Stores the exact time in ms when BLE disconnected
unsigned long emergencyStartTime = 0; // Stores the exact time in ms when Emergency Stop was triggered


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
class MyCallbacks : public BLECharacteristicCallbacks {   // A class called MyCallbacks that inherits the Characteristics of RX Channel monitoring from the BLECharacteristicCallbacks library
  void onWrite(BLECharacteristic* pCharacteristic) {  // get implemented immediately when the mobile app sends any message to ESP32-S
    String rxValue = pCharacteristic->getValue();  // getting the text received from the mobile app and temporarily storing it in "rxValue"
    rxValue.trim(); // Remove any leading/trailing spaces or newline characters (\r or \n)

    if (rxValue.length() > 0 && rxValue[0] >= 32 && rxValue[0] <= 126) { // Only accept non-empty printable ASCII text
      if (rxValue.equalsIgnoreCase("E") || rxValue.equalsIgnoreCase("STOP")) {  // Priority Check: Raise Emergency Stop flag immediately if 'E' or 'STOP' is received
        emergencyStopFlag = true; // Priority flag handled immediately at the top of loop()
        clearEmergencyFlag = false; // still not RECEIVED the clear emergency order
        Serial.println("!!!EMERGENCY STOP COMMAND RECEIVED!!!");  // print in serial monitor
      } 
      else if (rxValue.equalsIgnoreCase("CLEAR EMERGENCY") || rxValue.equalsIgnoreCase("CLEAR")) {  // 2. Priority Check: Resume operation if "CLEAR EMERGENCY" (or "CLEAR") is received
        clearEmergencyFlag = true;  // The Clear Emergency order got RECEIVED
        Serial.println(">>>CLEAR EMERGENCY COMMAND RECEIVED<<<");  // print in serial monitor
      }
      else {  // 3. normal operation
        receivedCommand = rxValue; // Store incoming command in global buffer
        newCommandReceived = true; // Raise flag so the FSM processes it
        Serial.print("Received from Mobile: ");
        Serial.println(receivedCommand);  // print the incoming message from mobile in serial monitor
      }
    }
  }
};



// Function Prototypes (Declaration of functions Below the void loop)
int angleToPulse(int angle);
void setupPCA9685();
bool wakeupServosNonBlocking();
void setTargetAnglesFromArray(const int angles[]);
bool updateServoSmooth();
bool updateSortingSequence();
void setupBLE();
void sendBLEMessage(String message);
void updateStatusLED();
int processIncomingCommand(String cmd);
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

  // 1. Highest Priority Guard: Enter STATE_EMERGENCY immediately on 'E' or 'STOP'
  if (emergencyStopFlag) {  // Check if the mobile app sent an Emergency Stop command ('E' or 'STOP') at any moment
    emergencyStopFlag = false;  // Reset the emergency stop flag after reading it so it doesn't trigger repeatedly
    clearEmergencyFlag = false; // Clear any pending clear-emergency flag to ensure safety
    newCommandReceived = false; // Remove any queued command so nothing executes during emergency

    // Only save target angles and start timer if we aren't already in STATE_EMERGENCY
    if (currentState != STATE_EMERGENCY) {  // Check that the robot is not already locked in STATE_EMERGENCY so we don't overwrite the saved angles or reset the timer
      for (int i = 0; i < NUM_SERVO; i++) {  // Repeat the Order for each of the 6 Servos
        savedTargetAngle[i] = targetAngle[i]; // Save the angle each servo was heading to before stopping, in case we resume later
        targetAngle[i] = currentAngle[i];     // Make the target angle equal to the current angle so all servos freeze immediately in place
      }
      emergencyStartTime = millis(); // Record the exact time in ms when Emergency Stop happened to start counting 1 minute
      currentState = STATE_EMERGENCY; // Move the robot immediately into the locked Emergency State
      sendBLEMessage("EMERGENCY_STOPPED"); // Send confirmation message to the mobile app that the robot has stopped
      Serial.println("!!! STATE_EMERGENCY ACTIVE -> 1-Minute Timer Started !!!"); // Print alert on Serial Monitor to follow up with the emergency state
    }
  }

  // Ignore stray "CLEAR EMERGENCY" commands if the robot is not in STATE_EMERGENCY
  if (currentState != STATE_EMERGENCY && clearEmergencyFlag) { // If the robot is not in Emergency State and a "CLEAR EMERGENCY" command arrived
    clearEmergencyFlag = false; // Ignore it and reset the flag so it doesn't stay stuck
  }

  // 2. Safety Guard: Reset State if Bluetooth Disconnects at any moment
  if (currentState != STATE_INIT_SERVOS && currentState != STATE_EMERGENCY && !deviceConnected && currentState != STATE_WAIT_BLE) {  // if The ESP32-S and mobile isn't connected and the Robot isn't in startup, emergency, or waiting to connect state
    newCommandReceived = false;  // Remove any command 
    currentSortStep = SORT_NONE; // Cancel any active sorting step if Bluetooth disconnected
    isSortingTask = false;       // Reset the sorting task flag back to false
    currentMode = MODE_STANDBY;  // Reset the mobile menu mode back to STANDBY so the next connection starts fresh
    currentState = STATE_WAIT_BLE; // Return the Robot to the waiting to connect state
    disconnectTime = millis();     // Record the exact moment BLE disconnected
    pendingAdvertising = true;     // Raise flag to restart advertising after 300ms
    Serial.println("BLE Disconnected!!! , Returning to WAIT_BLE_STATE");  // Print message to follow up with the change appears in Serial Monitor
  }

  // 300ms wait before restarting BLE advertising
  if (pendingAdvertising && (millis() - disconnectTime >= BLE_ADV_DELAY)) {  // checking the 300 ms
    pendingAdvertising = false;    // Lower the flag so advertising starts only once
    BLEDevice::startAdvertising(); // Restart BLE advertising cleanly after 300ms
    Serial.println("BLE Advertising Restarted."); // Print confirming message on Serial Monitor that Bluetooth is visible again
  }

  // 3. Main Finite State Machine (FSM)
  switch (currentState) {    // To look at currentState Value then jump to the Case of this value

    // State 0: Sequential Servo Wakeup at Startup (250ms per servo)
    case STATE_INIT_SERVOS: {  // if currentState == STATE_INIT_SERVOS , The "{}" after the ":" because a new Variable "allAwake" has meaning in this case only
      bool allAwake = wakeupServosNonBlocking(); // Call the wakeup function to energize one servo every 250ms 
      if (allAwake) { // Check if all 6 servos finished waking up gently
        currentState = STATE_WAIT_BLE; // yes? move to the next state to wait for mobile Bluetooth connection
        Serial.println("All Servos Initialized Gently -> Waiting for BLE Connection..."); // Printing confirming message
      }
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
    }

    // State 1: Waiting for the Mobile App Connection with ESP32-S
    case STATE_WAIT_BLE:   // if currentstate == STATE_WAIT_BLE 
      if (deviceConnected) {  // Check if ESP32-S Connected to the Mobile app
        newCommandReceived = false; // Clear any leftover command flag right when a new Bluetooth connection is established
        currentMode = MODE_STANDBY; // Ensure the system always starts in the main STANDBY menu when connected
        currentState = STATE_IDLE;  // if yes move to the next state
        Serial.println("BLE Connected , Entering IDLE State");   // Printing confirming message
      }
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // State 2: Connected & Waiting for New Command from mobile app
    case STATE_IDLE:   // if currentstate == STATE_IDLE
      if (newCommandReceived) {  // Since the Robot Becomes ready, it checks if there are any new commands
        newCommandReceived = false;  // yes? close the flag after you read it so the same message didn't get read twice
        currentState = STATE_PARSE_CMD;   // then move to the next state
      }
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // State 3: Check & Validate Incoming Command from mobile app
    case STATE_PARSE_CMD: {   // if currentstate == STATE_PARSE_CMD , The "{}" after the ":" because a new Variable "cmdResult" has meaning in this case only
      int cmdResult = processIncomingCommand(receivedCommand);  // The message from mobile app gets sent to "processIncomingCommand" function and the return value (0=Error, 1=Mode Changed, 2=Move/Sort) gets stored in "cmdResult"
      if (cmdResult == 2) {  // checking if the command is a valid servo movement or sorting command
        Serial.println("Valid Command -> Time to Move Servo Motors");  // true? means that the sent command was correct so we print a confirming message in the serial monitor
        sendBLEMessage(isSortingTask ? "SORTING..." : "Moving..."); // Send immediate acknowledgment message to the mobile app ("SORTING..." if sorting cycle, or "Moving..." if manual arm move)
        currentState = STATE_MOVING;  // then move to the next state
      } else if (cmdResult == 1) {  // checking if the command was only a menu/mode switch (like M, 1, 2, or 0)
        currentState = STATE_IDLE;  // Mode confirmation was already sent, so return directly to IDLE State to wait for the next command
      } else {  // cmdResult was 0 (invalid command or sent in the wrong mode)
        Serial.print("Invalid Command Received: "); // Print invalid command warning prefix on Serial Monitor before printing the rejected text
        Serial.println(receivedCommand); // Print the exact rejected command text on Serial Monitor for debugging
        sendBLEMessage("ERROR, Try again");  // send a message to the user of the mobile app to let him know he wrote the wrong command
        currentState = STATE_IDLE;  // move backward to the IDLE State
      }
      break;   // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
    }

    // State 4: Move Servo Motors Smoothly until Target Reached
    case STATE_MOVING: {   // if currentstate == STATE_MOVING , The "{}" after the ":" because new Variables have meaning in this case only
      if (newCommandReceived) { // Check if the user sent another normal command while the arm is still moving or sorting
        newCommandReceived = false; // Clear the flag and ignore the command so it doesn't interrupt the current movement
        sendBLEMessage("BUSY"); // Tell the mobile app that the robot is currently busy executing a task
        Serial.println("Command Rejected -> Robot is BUSY"); // Print notice on Serial Monitor that an extra command was blocked
      }

      bool missionComplete = false; // Variable to store whether the full movement or 5-step sorting sequence has finished
      if (isSortingTask) { // Check if the robot is currently running a 5-step automatic sorting sequence
        missionComplete = updateSortingSequence(); // Advance step-by-step through Grab, Lift, Move to Bin, Release, and Return Home
      } else { // Otherwise, it is a normal single-step manual movement (Arm Control or HOME)
        missionComplete = updateServoSmooth();  // in each cycle "updateServoSmooth" function get called and stores its value in "missionComplete" , as long as it's false, the servo motors move 1 angle degree each 30ms
      }

      if (missionComplete) {   // check the value of missionComplete
        currentState = STATE_FEEDBACK;  // true? means all the servo motors reached to their target angle so move to the next state
      }
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them
    }

    // State 5: Send Confirmation to Mobile App & Return to IDLE
    case STATE_FEEDBACK:  // if currentstate == STATE_FEEDBACK , note this is software code feedback not real feedback
      if (isSortingTask) { // Check if the finished task was a full sorting cycle
        sendBLEMessage("SORT_DONE"); // sending a confirm "SORT_DONE" message to the mobile app
        Serial.println("Sorting Complete -> Sent SORT_DONE"); // print a confirming message in the serial monitor that SORT_DONE got sent to the mobile app
        isSortingTask = false; // Reset the sorting task flag since the cycle is now finished
      } else { // Otherwise, it was a manual arm movement or HOME command
        sendBLEMessage("DONE");  // sending a confirm "DONE" message to the mobile app
        Serial.println("Movement Complete -> Sent DONE");  // print a confirming message in the serial monitor that the Done message got sent to the mobile app
      }
      currentState = STATE_IDLE;  // The Task is Done, return to the IDLE State
      break;  // The work in this case is done, move out of the switch and check the condition of other cases if you are going to jump into them

    // State 6: Locked Emergency State (Waits 1 Minute for "CLEAR EMERGENCY" or Auto-Returns HOME)
    case STATE_EMERGENCY:  // if currentstate == STATE_EMERGENCY , robot is frozen waiting up to 1 minute for "CLEAR EMERGENCY" or auto-homing
      if (clearEmergencyFlag) { // Check if the mobile app sent "CLEAR EMERGENCY" before the 1-minute timer expired
        clearEmergencyFlag = false; // Reset the clear emergency flag after reading it
        newCommandReceived = false; // Clear any leftover command flag
        for (int i = 0; i < NUM_SERVO; i++) { // Repeat the Order for each of the 6 Servos
          targetAngle[i] = savedTargetAngle[i]; // Restore the saved destination angles so the arm continues from where it stopped
        }
        sendBLEMessage("EMERGENCY_CLEARED"); // Tell the mobile app that emergency is cleared and sorting/movement is resuming
        Serial.println("Emergency Cleared -> Resuming Movement"); // Print confirming message on Serial Monitor
        currentState = STATE_MOVING; // Return to MOVING State to complete the interrupted movement or sorting step
      } else if (millis() - emergencyStartTime >= EMERGENCY_TIMEOUT_MS) { // Check if 1 full minute (60,000ms) has passed with no "CLEAR EMERGENCY" command
        currentSortStep = SORT_NONE; // Cancel the interrupted sorting sequence
        isSortingTask = false; // Reset sorting task flag so it only performs a simple return to HOME
        newCommandReceived = false; // Clear any leftover command flag
        for (int i = 0; i < NUM_SERVO; i++) { // Repeat the Order for each of the 6 Servos
          targetAngle[i] = HOME_ANGLES[i]; // Set target angles to safe HOME posture
        }
        sendBLEMessage("EMERGENCY_TIMEOUT -> Returning HOME"); // Inform the mobile app that 1 minute passed and the arm is returning home
        Serial.println("1-Minute Timeout -> Returning HOME Smoothly"); // Print message on Serial Monitor to follow up with the auto-return
        currentState = STATE_MOVING; // Move to MOVING State so the arm returns HOME smoothly (30ms per degree)
      } else if (newCommandReceived) { // Check if the user tried to send any normal command while still locked in Emergency
        newCommandReceived = false; // Ignore the command and clear the flag
        sendBLEMessage("LOCKED: Send CLEAR EMERGENCY"); // Remind the mobile app that the robot is locked in emergency mode
        Serial.println("Command Blocked -> Robot is in STATE_EMERGENCY"); // Print notice on Serial Monitor
      }
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


// Function 2: Initialize PCA9685 Driver Hardware (Servos wake up gently later in STATE_INIT_SERVOS)
void setupPCA9685() {  // This function won't return any value 
  Wire.begin(21, 22);  // Turning on the I2C Connection and pinout it to GPIO21 (FOR SDA) and GPIO22 (FOR SCL)

  Wire.beginTransmission(PCA9685_ADDR); // Start an I2C test transmission to check if the PCA9685 chip responds at address 0x40
  if (Wire.endTransmission() == 0) { // If endTransmission() returns 0, the PCA9685 acknowledged and is physically wired
    pcaConnected = true; // Set flag to true so the code knows PCA9685 hardware is available
    pwm.begin();  // Turning on the PCA9685 To make it ready to receive orders
    pwm.setPWMFreq(SERVO_FREQ); // Setting the Frequency of the out Pulses from the PCA9685 TO 50 HZ (THE VALUE OF THE CONSTANT NAMED SERVO_FREQ)
    Serial.println("PCA9685 Connected & Frequency Set (50Hz)."); // Print confirmation on Serial Monitor that PCA9685 hardware was detected
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

// Function 3: Non-Blocking Sequential Servo Wakeup at Startup (250ms per servo using millis)
bool wakeupServosNonBlocking() { // Returns true only after all 6 servos have been energized one by one
  if (millis() - lastServoWakeupTime < SERVO_WAKEUP_INTERVAL) { // Wait until 250ms has passed since the last servo wakeup without blocking the loop
    return false; // Not yet time for the next servo
  }
  lastServoWakeupTime = millis(); // Record the current time in ms for the next 250ms interval

  if (wakeupServoIndex < NUM_SERVO) { // Check if there are still servos left to wake up (from index 0 to 5)
    if (pcaConnected) { // Only send I2C PWM signal if PCA9685 board is physically connected
      int startPulse = angleToPulse(currentAngle[wakeupServoIndex]); // Convert initial HOME angle of this servo to pulse ticks
      pwm.setPWM(wakeupServoIndex, 0, startPulse); // Energize ONLY this single servo gently
    }
    Serial.print("Gently Woke Up Servo #"); // Print progress on Serial Monitor
    Serial.println(wakeupServoIndex);
    wakeupServoIndex++; // Move counter to the next servo for the next 250ms cycle
    return false; // Still waking up servos (gives the last servo 250ms to settle too)
  }

  return true; // All 6 servos are awake and settled; ready to move to STATE_WAIT_BLE
}


// Function 4: Helper to Copy a 6-Servo Angle Array into targetAngle[]
void setTargetAnglesFromArray(const int angles[]) { // Copies a preset posture (HOME or BIN) into the active targetAngle array
  for (int i = 0; i < NUM_SERVO; i++) { // Repeat for each of the 6 servos
    targetAngle[i] = angles[i]; // Set each joint's target angle from the preset array
  }
}


// Function 5: 5-Step Automatic Sorting Sequence Controller 
bool updateSortingSequence() { // Advances through Grab -> Lift -> Move to Bin -> Release -> Return Home; returns true when full cycle finishes
  bool stepReached = updateServoSmooth(); // Move servos 1 degree every 30ms toward the current sorting step's target angles

  if (!stepReached) { // Check if the servos are still moving toward the current step's destination
    return false; // Keep running the current step until all 6 joints reach their target angles
  }

  // If stepReached is true, the current sorting step has completed -> transition to the next step!
  switch (currentSortStep) {

    case SORT_GRAB: // Step 1 finished (Gripper closed firmly on the object) -> Start Step 2 (Lift Arm)
      Serial.println("Sort Step 1/5 Done (Grabbed) -> Step 2/5: Lifting Object...");
      currentSortStep = SORT_LIFT; // Advance sub-state to lifting
      targetAngle[1] = LIFT_SHOULDER_ANGLE; // Raise Shoulder to safe clearance height
      targetAngle[2] = LIFT_ELBOW_ANGLE;    // Adjust Elbow to safe clearance height
      return false; // Sequence is not finished yet

    case SORT_LIFT: // Step 2 finished (Object lifted clear of platform) -> Start Step 3 (Move Above Target Bin)
      Serial.println("Sort Step 2/5 Done (Lifted) -> Step 3/5: Moving to Target Bin...");
      currentSortStep = SORT_TO_BIN; // Advance sub-state to moving toward the selected bin
      for (int i = 0; i < NUM_SERVO; i++) { // Load the pre-selected bin angles (Bin 1, 2, or 3) into targetAngle
        targetAngle[i] = activeBinAngles[i];
      }
      return false; // Sequence is not finished yet

    case SORT_TO_BIN: // Step 3 finished (Arm positioned directly over target bin) -> Start Step 4 (Open Gripper)
      Serial.println("Sort Step 3/5 Done (At Bin) -> Step 4/5: Releasing Object...");
      currentSortStep = SORT_RELEASE; // Advance sub-state to releasing the object
      targetAngle[5] = GRIPPER_OPEN_ANGLE; // Open the gripper fingers so the object drops into the bin
      return false; // Sequence is not finished yet

    case SORT_RELEASE: // Step 4 finished (Object dropped into bin) -> Start Step 5 (Return to Safe HOME)
      Serial.println("Sort Step 4/5 Done (Released) -> Step 5/5: Returning HOME...");
      currentSortStep = SORT_RETURN_HOME; // Advance sub-state to returning back to ready position
      setTargetAnglesFromArray(HOME_ANGLES); // Set target angles back to HOME_ANGLES above the blue pick platform
      return false; // Sequence is not finished yet

    case SORT_RETURN_HOME: // Step 5 finished (Arm is back at HOME_ANGLES) -> Entire Sorting Mission Complete!
      Serial.println("Sort Step 5/5 Done -> Sorting Cycle Finished!");
      currentSortStep = SORT_NONE; // Reset sorting sub-state back to none
      return true; // Return true to tell STATE_MOVING the whole sorting cycle is complete!

    default: // Safety fallback
      currentSortStep = SORT_NONE;
      return true;
  }
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

// Function 5: Strict Hierarchical Command & Mode Dispatcher
// Returns: 0 = Invalid Command or Wrong Mode | 1 = Mode Changed (No Servo Motion) | 2 = Valid Motion or Sorting Started
int processIncomingCommand(String cmd) {
  cmd.trim(); // Remove any extra spaces or newline characters
  cmd.toUpperCase(); // Convert command to uppercase so 'm', 'r', 'arm' work just like 'M', 'R', 'ARM'

  if (cmd.length() == 0) { // Reject empty commands
    return 0;
  }

  // Global Exit / Back Navigation Commands (Work from any active sub-mode)
  if (cmd == "0" || cmd == "EXIT") { // Return all the way back to the Main Standby Menu
    currentMode = MODE_STANDBY;
    sendBLEMessage("MODE:STANDBY");
    Serial.println("Switched Mode -> MODE_STANDBY");
    return 1;
  }
  if (cmd == "BACK") { // Go back one menu level
    if (currentMode == MODE_ARM_CONTROL || currentMode == MODE_MANUAL_SORT) {
      currentMode = MODE_MANUAL_MENU;
      sendBLEMessage("MODE:MANUAL_MENU");
      Serial.println("Switched Mode -> MODE_MANUAL_MENU");
    } else {
      currentMode = MODE_STANDBY;
      sendBLEMessage("MODE:STANDBY");
      Serial.println("Switched Mode -> MODE_STANDBY");
    }
    return 1;
  }

  // Enforce Strict Hierarchical Mode Flow: STANDBY -> ('M') -> MANUAL_MENU -> ('1' or '2')
  switch (currentMode) {

    // Level 1: Main Standby Menu (Must receive 'M' first to enter Manual Mode)
    case MODE_STANDBY:
      if (cmd == "M" || cmd == "MANUAL") {
        currentMode = MODE_MANUAL_MENU; // Enter Manual Mode Menu
        sendBLEMessage("MODE:MANUAL_MENU");
        Serial.println("Entered Manual Mode -> Waiting for Sub-Mode ('1' Arm Control or '2' Manual Sort)");
        return 1;
      }
      return 0; // Block everything else until 'M' is received

    // Level 2: Inside Manual Mode Menu (Must choose '1' Arm Control or '2' Manual Sorting)
    case MODE_MANUAL_MENU:
      if (cmd == "1" || cmd == "ARM") {
        currentMode = MODE_ARM_CONTROL; // Enter Sub-Mode 1: Direct Robotic Arm Control
        sendBLEMessage("MODE:ARM_CONTROL");
        Serial.println("Entered Sub-Mode 1 -> Robotic Arm Control");
        return 1;
      } 
      else if (cmd == "2" || cmd == "SORT") {
        currentMode = MODE_MANUAL_SORT; // Enter Sub-Mode 2: 3-Bin Manual Sorting
        sendBLEMessage("MODE:MANUAL_SORT");
        Serial.println("Entered Sub-Mode 2 -> Manual Sorting");
        return 1;
      }
      return 0; // Block angles or sorting commands until '1' or '2' is chosen

    // Level 3A: Robotic Arm Control Sub-Mode (Accepts "0:90,1:45" or "H"/"HOME")
    case MODE_ARM_CONTROL:
      if (cmd == "H" || cmd == "HOME") {
        isSortingTask = false;
        currentSortStep = SORT_NONE;
        setTargetAnglesFromArray(HOME_ANGLES); // Move smoothly back to HOME posture
        return 2;
      }
      if (parseCommand(cmd)) { // Validate joint:angle pairs using our existing parser
        isSortingTask = false;
        currentSortStep = SORT_NONE;
        return 2;
      }
      return 0;

    // Level 3B: Manual Sorting Sub-Mode (Accepts 3-Bin Sorting Letters or "H"/"HOME")
    case MODE_MANUAL_SORT:
      if (cmd == "H" || cmd == "HOME") {
        isSortingTask = false;
        currentSortStep = SORT_NONE;
        setTargetAnglesFromArray(HOME_ANGLES); // Move smoothly back to HOME posture
        return 2;
      }

      // Check Bin 1 Letters: Red ('R'), Square/Rectangle ('S'), Paper ('P')
      if (cmd == "R" || cmd == "S" || cmd == "P") {
        for (int i = 0; i < NUM_SERVO; i++) {
          activeBinAngles[i] = BIN1_ANGLES[i]; // Load Bin 1 destination posture
        }
        Serial.println("Target Selected -> BIN 1 (Red / Square / Paper)");
      }
      // Check Bin 2 Letters: Blue ('B'), Triangle ('T'), Plastic ('L')
      else if (cmd == "B" || cmd == "T" || cmd == "L") {
        for (int i = 0; i < NUM_SERVO; i++) {
          activeBinAngles[i] = BIN2_ANGLES[i]; // Load Bin 2 destination posture
        }
        Serial.println("Target Selected -> BIN 2 (Blue / Triangle / Plastic)");
      }
      // Check Bin 3 Letters: Green ('G'), Circle ('C'), Glass ('Z')
      else if (cmd == "G" || cmd == "C" || cmd == "Z") {
        for (int i = 0; i < NUM_SERVO; i++) {
          activeBinAngles[i] = BIN3_ANGLES[i]; // Load Bin 3 destination posture
        }
        Serial.println("Target Selected -> BIN 3 (Green / Circle / Glass)");
      }
      else {
        return 0; // Unrecognized command in Manual Sorting mode
      }

      // Initialize the 5-Step Sorting Sequence starting with Step 1 (Grabbing the object)
      isSortingTask = true;
      currentSortStep = SORT_GRAB;
      targetAngle[5] = GRIPPER_CLOSE_ANGLE; // Step 1 target: close gripper on the object below
      return 2;

    default:
      return 0;
  }
}