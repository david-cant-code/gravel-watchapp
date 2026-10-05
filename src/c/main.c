#include <pebble.h>

#include "flow.h"

_Static_assert((int)FLOW_STATUS_SUCCESS == (int)DictationSessionStatusSuccess, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_REJECTED == (int)DictationSessionStatusFailureTranscriptionRejected, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_REJECTED_WITH_ERROR == (int)DictationSessionStatusFailureTranscriptionRejectedWithError,
               "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_SYSTEM_ABORTED == (int)DictationSessionStatusFailureSystemAborted, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_NO_SPEECH == (int)DictationSessionStatusFailureNoSpeechDetected, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_CONNECTIVITY == (int)DictationSessionStatusFailureConnectivityError, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_DISABLED == (int)DictationSessionStatusFailureDisabled, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_INTERNAL_ERROR == (int)DictationSessionStatusFailureInternalError, "status values follow pebble.h");
_Static_assert((int)FLOW_STATUS_RECOGNIZER_ERROR == (int)DictationSessionStatusFailureRecognizerError, "status values follow pebble.h");
_Static_assert((int)FLOW_LAUNCH_QUICK_LAUNCH == (int)APP_LAUNCH_QUICK_LAUNCH, "launch reasons follow pebble.h");

#define STATUS_TEXT_MAX 160
// Quick Launch starts recording from this timer, outside the first window's push. Started inside it, the push
// clears the listening screen's click config (PebbleOS 70ed290, src/fw/applib/ui/window_stack.c,
// prv_set_new_window_on_screen), which the voice window sets up again only once recording starts
// (src/fw/applib/voice/voice_window.c, prv_do_transition). 300 ms is the delay tried on a watch; shorter is untried.
#define AUTOSTART_DELAY_MS 300

static Window *s_menu_window;
static MenuLayer *s_menu_layer;
static Window *s_status_window;
static TextLayer *s_status_layer;
static char s_status_text[STATUS_TEXT_MAX];
static DictationSession *s_session;
static AppTimer *s_leave_timer;
static AppTimer *s_autostart_timer;
// Quick Launch records at once and closes the app when done; the app list opens the "+ Record new" menu.
static bool s_quick_launch;

static void cancel_leave_timer(void) {
  if (s_leave_timer) {
    app_timer_cancel(s_leave_timer);
    s_leave_timer = NULL;
  }
}

static void leave_status(void) {
  cancel_leave_timer();
  switch (flow_leave_action(s_quick_launch)) {
    case FLOW_LEAVE_CLOSE_APP:
      window_stack_pop_all(true);
      break;
    case FLOW_LEAVE_TO_MENU:
      if (window_stack_contains_window(s_status_window)) {
        window_stack_remove(s_status_window, true);
      }
      break;
  }
}

static void leave_timer_fired(void *context) {
  s_leave_timer = NULL;
  leave_status();
}

// On round screens text flow follows the circle from the position the layer had when flow was enabled, so it is
// enabled again after every frame change (PebbleOS 70ed290, src/fw/applib/ui/text_layer_flow.c,
// text_layer_calc_text_flow_paging_values).
static void set_status_frame(GRect frame) {
  layer_set_frame(text_layer_get_layer(s_status_layer), frame);
#if defined(PBL_ROUND)
  text_layer_enable_screen_text_flow_and_paging(s_status_layer, 4);
#endif
}

// Measures the text in a full-height box, then centers a box of that height.
static void layout_status_text(void) {
  GRect bounds = layer_get_bounds(window_get_root_layer(s_status_window));
  GRect text_box = grect_inset(bounds, GEdgeInsets(0, 6));
  set_status_frame(text_box);
  text_layer_set_text(s_status_layer, s_status_text);
  int16_t height = text_layer_get_content_size(s_status_layer).h + 8;
  if (height > text_box.size.h) {
    height = text_box.size.h;
  }
  text_box.origin.y = (bounds.size.h - height) / 2;
  text_box.size.h = height;
  set_status_frame(text_box);
}

static void show_outcome(FlowOutcome outcome) {
  if (outcome.kind == FLOW_CANCELLED) {
    leave_status();
    return;
  }
  flow_copy_text(s_status_text, sizeof(s_status_text), outcome.text);
  if (!window_stack_contains_window(s_status_window)) {
    window_stack_push(s_status_window, true);
  }
  layout_status_text();
  cancel_leave_timer();
  s_leave_timer = app_timer_register(outcome.show_ms, leave_timer_fired, NULL);
}

static void dictation_done(DictationSession *session, DictationSessionStatus status, char *transcription,
                           void *context) {
  show_outcome(flow_outcome(status, transcription, connection_service_peek_pebble_app_connection()));
}

static void start_recording(void) {
  cancel_leave_timer();
  if (s_autostart_timer) {
    app_timer_cancel(s_autostart_timer);
    s_autostart_timer = NULL;
  }
  // Created on first use: creation fails while the phone is away, and a later press should still work.
  if (!s_session) {
    s_session = dictation_session_create(0, dictation_done, NULL);
    if (!s_session) {
      show_outcome(flow_no_session(connection_service_peek_pebble_app_connection()));
      return;
    }
    dictation_session_enable_confirmation(s_session, false);
    dictation_session_enable_error_dialogs(s_session, false);
  }
  DictationSessionStatus started = dictation_session_start(s_session);
  if (started != DictationSessionStatusSuccess) {
    show_outcome(flow_outcome(started, NULL, connection_service_peek_pebble_app_connection()));
  }
}

static uint16_t menu_rows(MenuLayer *menu, uint16_t section, void *context) {
  return 1;
}

static void menu_draw_row(GContext *ctx, const Layer *cell, MenuIndex *index, void *context) {
  menu_cell_basic_draw(ctx, cell, "+ Record new", NULL, NULL);
}

static void menu_select(MenuLayer *menu, MenuIndex *index, void *context) {
  start_recording();
}

static void menu_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  s_menu_layer = menu_layer_create(layer_get_bounds(root));
  menu_layer_set_callbacks(s_menu_layer, NULL, (MenuLayerCallbacks){
    .get_num_rows = menu_rows,
    .draw_row = menu_draw_row,
    .select_click = menu_select,
  });
  menu_layer_set_click_config_onto_window(s_menu_layer, window);
  layer_add_child(root, menu_layer_get_layer(s_menu_layer));
}

static void menu_window_unload(Window *window) {
  menu_layer_destroy(s_menu_layer);
}

static void status_select(ClickRecognizerRef recognizer, void *context) {
  start_recording();
}

static void status_click_config(void *context) {
  window_single_click_subscribe(BUTTON_ID_SELECT, status_select);
}

static void status_window_load(Window *window) {
  s_status_layer = text_layer_create(GRectZero);
  text_layer_set_font(s_status_layer, fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD));
  text_layer_set_text_alignment(s_status_layer, GTextAlignmentCenter);
  text_layer_set_overflow_mode(s_status_layer, GTextOverflowModeTrailingEllipsis);
  layer_add_child(window_get_root_layer(window), text_layer_get_layer(s_status_layer));
}

static void autostart_fired(void *context) {
  s_autostart_timer = NULL;
  start_recording();
}

static void status_window_unload(Window *window) {
  cancel_leave_timer();
  text_layer_destroy(s_status_layer);
}

int main(void) {
  s_quick_launch = flow_is_quick_launch(launch_reason());

  s_status_window = window_create();
  window_set_click_config_provider(s_status_window, status_click_config);
  window_set_window_handlers(s_status_window, (WindowHandlers){
    .load = status_window_load,
    .unload = status_window_unload,
  });

  if (s_quick_launch) {
    window_stack_push(s_status_window, false);
    s_autostart_timer = app_timer_register(AUTOSTART_DELAY_MS, autostart_fired, NULL);
  } else {
    s_menu_window = window_create();
    window_set_window_handlers(s_menu_window, (WindowHandlers){
      .load = menu_window_load,
      .unload = menu_window_unload,
    });
    window_stack_push(s_menu_window, true);
  }

  app_event_loop();

  if (s_session) {
    dictation_session_destroy(s_session);
  }
  window_destroy(s_status_window);
  if (s_menu_window) {
    window_destroy(s_menu_window);
  }
}
