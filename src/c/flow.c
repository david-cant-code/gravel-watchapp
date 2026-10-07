#include "flow.h"

#include <string.h>

#define TEXT_NOTHING_HEARD "Didn't catch that"
#define TEXT_NO_PHONE "Phone not connected"
#define TEXT_VOICE_OFF "Voice is off on the phone"
#define TEXT_UNSUPPORTED "Phone app can't take recordings"
#define TEXT_ERROR "Something went wrong. Try again."

// "Saved" stays up about 2 s; longer answers get another second per 20 characters, up to 6 s.
#define SHOW_MS_BASE 2000
#define SHOW_MS_STEP 1000
#define SHOW_MS_MAX 6000
#define SHOW_CHARS_PER_STEP 20

static bool is_utf8_continuation(char c) {
  return ((unsigned char)c & 0xC0) == 0x80;
}

bool flow_is_quick_launch(int launch_reason) {
  return launch_reason == FLOW_LAUNCH_QUICK_LAUNCH;
}

FlowLeave flow_leave_action(bool quick_launch) {
  return quick_launch ? FLOW_LEAVE_CLOSE_APP : FLOW_LEAVE_TO_MENU;
}

void flow_cancel_sent(FlowCancel *cancel) {
  cancel->in_flight = true;
  cancel->holding = true;
}

bool flow_cancel_settled(FlowCancel *cancel) {
  bool leave = cancel->holding;
  cancel->in_flight = false;
  cancel->holding = false;
  return leave;
}

bool flow_cancel_hold_over(FlowCancel *cancel) {
  bool leave = cancel->holding;
  cancel->holding = false;
  return leave;
}

bool flow_may_record(const FlowCancel *cancel) {
  return !cancel->in_flight;
}

bool flow_back_leaves(const FlowCancel *cancel) {
  return !cancel->holding;
}

uint32_t flow_show_ms(const char *text) {
  size_t chars = 0;
  for (const char *c = text; c && *c; c++) {
    if (!is_utf8_continuation(*c)) {
      chars++;
    }
  }
  size_t extra_steps = chars > SHOW_CHARS_PER_STEP ? (chars - 1) / SHOW_CHARS_PER_STEP : 0;
  uint32_t ms = SHOW_MS_BASE + (uint32_t)extra_steps * SHOW_MS_STEP;
  return ms > SHOW_MS_MAX ? SHOW_MS_MAX : ms;
}

static FlowOutcome show(const char *text) {
  return (FlowOutcome){.kind = FLOW_SHOW, .text = text, .show_ms = flow_show_ms(text)};
}

FlowOutcome flow_outcome(int status, const char *transcription, bool phone_connected) {
  switch (status) {
    case FLOW_STATUS_SUCCESS:
      return show(transcription && transcription[0] ? transcription : TEXT_NOTHING_HEARD);
    case FLOW_STATUS_REJECTED:
    case FLOW_STATUS_REJECTED_WITH_ERROR:
      return (FlowOutcome){.kind = FLOW_CANCELLED};
  }
  if (!phone_connected) {
    return show(TEXT_NO_PHONE);
  }
  switch (status) {
    // Also a phone's result-stage error with no speech-detected event after the first 600 ms, when error
    // dialogs are off (PebbleOS 70ed290, src/fw/applib/voice/voice_window.c, prv_handle_dictation_error).
    case FLOW_STATUS_NO_SPEECH:
      return show(TEXT_NOTHING_HEARD);
    // A connected phone answering "service unavailable" arrives as a connectivity error too
    // (PebbleOS 70ed290, src/fw/services/voice/voice.c, prv_get_status_from_result).
    case FLOW_STATUS_CONNECTIVITY:
      return show(TEXT_ERROR);
    case FLOW_STATUS_DISABLED:
      return show(TEXT_VOICE_OFF);
    default:
      return show(TEXT_ERROR);
  }
}

FlowOutcome flow_no_session(bool phone_connected) {
  return show(phone_connected ? TEXT_UNSUPPORTED : TEXT_NO_PHONE);
}

size_t flow_copy_text(char *dst, size_t cap, const char *src) {
  if (cap == 0) {
    return 0;
  }
  size_t len = src ? strlen(src) : 0;
  if (len >= cap) {
    len = cap - 1;
    while (len > 0 && is_utf8_continuation(src[len])) {
      len--;
    }
  }
  if (len > 0) {
    memcpy(dst, src, len);
  }
  dst[len] = '\0';
  return len;
}
