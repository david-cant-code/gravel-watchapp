#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// The recording flow's decisions, kept free of pebble.h so they build and run on the host in tests.

// Values of pebble.h DictationSessionStatus and AppLaunchReason; main.c asserts they match at compile time.
enum {
  FLOW_STATUS_SUCCESS = 0,
  FLOW_STATUS_REJECTED = 1,
  FLOW_STATUS_REJECTED_WITH_ERROR = 2,
  FLOW_STATUS_SYSTEM_ABORTED = 3,
  FLOW_STATUS_NO_SPEECH = 4,
  FLOW_STATUS_CONNECTIVITY = 5,
  FLOW_STATUS_DISABLED = 6,
  FLOW_STATUS_INTERNAL_ERROR = 7,
  FLOW_STATUS_RECOGNIZER_ERROR = 8,
};

enum { FLOW_LAUNCH_QUICK_LAUNCH = 5 };

// The contract with Gravel: the keys of the app's messages. The cancel is sent when BACK ends a recording or the wait
// for its answer; Gravel drops the recording when it arrives within its short wait after the recording ends. Gravel
// acknowledges the ping and does not read its value.
enum { FLOW_CANCEL_KEY = 1, FLOW_PING_KEY = 2 };

// How long a cancel holds a blank screen with a BACK press ignored, so leaving does not drop the message unsent:
// PebbleOS drops an exiting app's unsent messages (PebbleOS 70ed290, src/fw/process_management/app_manager.c,
// prv_app_cleanup). The hold runs from BACK, so after Quick Launch a cancel still waiting behind a ping when it ends
// is dropped.
#define FLOW_CANCEL_HOLD_MS 2000

// A cancel on its way to the phone. No recording starts until the message settles (ACK, NACK or the firmware's
// timeout), since Gravel applies a cancel to whatever recording is in progress.
typedef struct {
  bool in_flight;
  bool holding;
} FlowCancel;

typedef struct {
  bool in_flight;
  bool cancel_waiting;
} FlowPing;

// Which message an outbox callback settled, and what follows from it.
typedef enum {
  FLOW_SETTLED_CANCEL,
  FLOW_SETTLED_PING,
  FLOW_SETTLED_PING_SEND_CANCEL,  // a cancel was waiting for the ping and goes now
} FlowSettled;

typedef enum {
  FLOW_SHOW,       // show text on the status screen for show_ms, then leave it
  FLOW_CANCELLED,  // the user backed out of the recording: leave at once, nothing to show
} FlowKind;

typedef struct {
  FlowKind kind;
  const char *text;
  uint32_t show_ms;
} FlowOutcome;

typedef enum {
  FLOW_LEAVE_CLOSE_APP,  // Quick Launch: back to the watchface
  FLOW_LEAVE_TO_MENU,    // opened from the app list: back to "+ Record new"
} FlowLeave;

bool flow_is_quick_launch(int launch_reason);

FlowLeave flow_leave_action(bool quick_launch);

void flow_cancel_sent(FlowCancel *cancel);

// The message settled; returns whether the held screen is left now.
bool flow_cancel_settled(FlowCancel *cancel);

// The hold ran out; returns whether the held screen is left now.
bool flow_cancel_hold_over(FlowCancel *cancel);

bool flow_may_record(const FlowCancel *cancel);

bool flow_back_leaves(const FlowCancel *cancel);

// The app has one outbox, so the ping and the cancel take turns: a cancel asked for while a ping is out is sent when
// the ping settles.
bool flow_may_ping(const FlowPing *ping, const FlowCancel *cancel);

void flow_ping_sent(FlowPing *ping);

// Returns whether the cancel has to wait for the ping, and if so marks it as waiting.
bool flow_cancel_waits_for_ping(FlowPing *ping);

// The ping settled; returns whether a waiting cancel is to be sent now.
bool flow_ping_settled(FlowPing *ping);

// At most one message is out at a time, so a settled message is the ping while one is in flight, else the cancel.
FlowSettled flow_outbox_settled(FlowPing *ping);

// The phone's answer is shown as it arrives: the phone decides the wording ("Saved", or why it refused).
// Any failure while the watch has no phone connection says so.
FlowOutcome flow_outcome(int status, const char *transcription, bool phone_connected);

// For when no dictation session can be created: no phone, or a phone app without app dictation.
FlowOutcome flow_no_session(bool phone_connected);

uint32_t flow_show_ms(const char *text);

// Copies at most cap - 1 bytes of src without cutting a UTF-8 character: PebbleOS draws nothing for a string
// that ends inside one (PebbleOS 70ed290, src/fw/applib/graphics/text_layout.c, graphics_draw_text).
// Returns the number of bytes copied.
size_t flow_copy_text(char *dst, size_t cap, const char *src);
