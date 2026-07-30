## L’APAVE Safety Requirements

### 1. Dropped-box alarm

When a dropped box is detected:

* The robot shall stop immediately.
* A dropped-box alarm shall be triggered.
* The alarm message displayed in the log shall be written in French.

Recommended French log message:

**« Chute de carton détectée. »**

### 2. Compressed-air presence check

DI22 is used to monitor the presence of compressed air:

* **DI22 = ON:** compressed air is available.
* **DI22 = OFF:** no compressed air is available.

Before the operator acknowledges the project start, the robot shall check the status of DI22.

If DI22 is OFF:

1. The project shall not start.
2. The buzzer shall be activated for approximately 10 to 15 seconds.
3. A French error message shall be displayed in the log.
4. After the buzzer duration has elapsed, the project shall stop and remain stopped until the fault has been resolved.

Recommended French log message:

**« Absence d’air comprimé. Veuillez vérifier l’alimentation pneumatique. »**
