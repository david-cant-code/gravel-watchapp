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
