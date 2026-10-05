#include <stdio.h>
#include <string.h>

#include "../src/c/flow.h"

static int failures;

#define CHECK(cond)                                                       \
  do {                                                                    \
    if (!(cond)) {                                                        \
      fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond); \
      failures++;                                                         \
    }                                                                     \
  } while (0)

#define CHECK_TEXT(outcome, expected) \
  CHECK((outcome).kind == FLOW_SHOW && (outcome).text && strcmp((outcome).text, (expected)) == 0)

static void test_quick_launch_is_the_only_launch_that_records(void) {
  CHECK(flow_is_quick_launch(FLOW_LAUNCH_QUICK_LAUNCH));
  for (int reason = 0; reason <= 7; reason++) {
    if (reason != FLOW_LAUNCH_QUICK_LAUNCH) {
      CHECK(!flow_is_quick_launch(reason));
    }
  }
}

static void test_success_shows_the_phone_text(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SUCCESS, "Saved", true), "Saved");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SUCCESS, "Couldn't save: too many recordings waiting", true),
             "Couldn't save: too many recordings waiting");
}

static void test_success_without_text_counts_as_nothing_heard(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SUCCESS, NULL, true), "Didn't catch that");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SUCCESS, "", true), "Didn't catch that");
}

static void test_back_during_recording_cancels(void) {
  CHECK(flow_outcome(FLOW_STATUS_REJECTED, NULL, true).kind == FLOW_CANCELLED);
  CHECK(flow_outcome(FLOW_STATUS_REJECTED_WITH_ERROR, NULL, true).kind == FLOW_CANCELLED);
}

static void test_failures_show_fixed_texts(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_NO_SPEECH, NULL, true), "Didn't catch that");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_DISABLED, NULL, true), "Voice is off on the phone");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SYSTEM_ABORTED, NULL, true), "Something went wrong. Try again.");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_INTERNAL_ERROR, NULL, true), "Something went wrong. Try again.");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_RECOGNIZER_ERROR, NULL, true), "Something went wrong. Try again.");
  CHECK_TEXT(flow_outcome(99, NULL, true), "Something went wrong. Try again.");
}

static void test_connectivity_says_no_phone_only_without_a_phone(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_CONNECTIVITY, NULL, false), "Phone not connected");
  CHECK_TEXT(flow_outcome(FLOW_STATUS_CONNECTIVITY, NULL, true), "Something went wrong. Try again.");
}

static void test_every_failure_without_a_phone_says_so(void) {
  int failures_from_phone[] = {FLOW_STATUS_SYSTEM_ABORTED, FLOW_STATUS_NO_SPEECH, FLOW_STATUS_DISABLED,
                               FLOW_STATUS_INTERNAL_ERROR, FLOW_STATUS_RECOGNIZER_ERROR, 99};
  for (size_t i = 0; i < sizeof(failures_from_phone) / sizeof(failures_from_phone[0]); i++) {
    CHECK_TEXT(flow_outcome(failures_from_phone[i], NULL, false), "Phone not connected");
  }
}

static void test_success_and_cancel_do_not_depend_on_the_phone_connection(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_SUCCESS, "Saved", false), "Saved");
  CHECK(flow_outcome(FLOW_STATUS_REJECTED, NULL, false).kind == FLOW_CANCELLED);
  CHECK(flow_outcome(FLOW_STATUS_REJECTED_WITH_ERROR, NULL, false).kind == FLOW_CANCELLED);
}

static void test_leaving_closes_after_quick_launch_and_returns_to_the_menu_otherwise(void) {
  CHECK(flow_leave_action(true) == FLOW_LEAVE_CLOSE_APP);
  CHECK(flow_leave_action(false) == FLOW_LEAVE_TO_MENU);
}

static void test_copy_keeps_short_text_whole(void) {
  char buf[16];
  CHECK(flow_copy_text(buf, sizeof(buf), "Saved") == 5);
  CHECK(strcmp(buf, "Saved") == 0);
  CHECK(flow_copy_text(buf, sizeof(buf), NULL) == 0);
  CHECK(buf[0] == '\0');
}

static void test_copy_cuts_ascii_at_the_buffer_size(void) {
  char buf[6];
  CHECK(flow_copy_text(buf, sizeof(buf), "Saved. Waiting") == 5);
  CHECK(strcmp(buf, "Saved") == 0);
}

static void test_copy_never_ends_inside_a_utf8_character(void) {
  // "ab" then U+2019 (3 bytes): a 5-byte buffer holds 4 bytes, which would end inside the apostrophe.
  char buf[5];
  CHECK(flow_copy_text(buf, sizeof(buf), "ab\xE2\x80\x99s") == 2);
  CHECK(strcmp(buf, "ab") == 0);
  char fits[6];
  CHECK(flow_copy_text(fits, sizeof(fits), "ab\xE2\x80\x99s") == 5);
  CHECK(strcmp(fits, "ab\xE2\x80\x99") == 0);
}

static void test_failure_texts_ignore_any_transcription(void) {
  CHECK_TEXT(flow_outcome(FLOW_STATUS_NO_SPEECH, "Saved", true), "Didn't catch that");
}

static void test_no_session_tells_missing_phone_from_unsupported_phone_app(void) {
  CHECK_TEXT(flow_no_session(false), "Phone not connected");
  CHECK_TEXT(flow_no_session(true), "Phone app can't take recordings");
}

static void test_show_time_grows_with_text_length(void) {
  CHECK(flow_show_ms(NULL) == 2000);
  CHECK(flow_show_ms("Saved") == 2000);
  CHECK(flow_show_ms("12345678901234567890") == 2000);
  CHECK(flow_show_ms("123456789012345678901") == 3000);
  CHECK(flow_show_ms("Saved. Waiting for Wi-Fi") == 3000);
  CHECK(flow_show_ms("Couldn't save: too many recordings waiting") == 4000);
  char long_text[200];
  memset(long_text, 'x', sizeof(long_text) - 1);
  long_text[sizeof(long_text) - 1] = '\0';
  CHECK(flow_show_ms(long_text) == 6000);
  CHECK(flow_show_ms("1234567890123456789012345678901234567890") == 3000);
  CHECK(flow_show_ms("12345678901234567890123456789012345678901") == 4000);
  CHECK(flow_show_ms("12345678901234567890123456789012345678901234567890123456789012345678901234567890") == 5000);
  CHECK(flow_show_ms("123456789012345678901234567890123456789012345678901234567890123456789012345678901") == 6000);
}

static void test_show_time_counts_characters_not_bytes(void) {
  // 20 characters, 40 bytes: each U+00E9 is 2 bytes.
  CHECK(flow_show_ms("\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9"
                     "\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9\xC3\xA9") == 2000);
}

static void test_outcomes_carry_their_show_time(void) {
  CHECK(flow_outcome(FLOW_STATUS_SUCCESS, "Saved", true).show_ms == 2000);
  CHECK(flow_outcome(FLOW_STATUS_SUCCESS, "Saved. Waiting for Wi-Fi", true).show_ms == 3000);
  CHECK(flow_no_session(true).show_ms == flow_show_ms("Phone app can't take recordings"));
}

int main(void) {
  test_quick_launch_is_the_only_launch_that_records();
  test_success_shows_the_phone_text();
  test_success_without_text_counts_as_nothing_heard();
  test_back_during_recording_cancels();
  test_failures_show_fixed_texts();
  test_failure_texts_ignore_any_transcription();
  test_connectivity_says_no_phone_only_without_a_phone();
  test_every_failure_without_a_phone_says_so();
  test_success_and_cancel_do_not_depend_on_the_phone_connection();
  test_leaving_closes_after_quick_launch_and_returns_to_the_menu_otherwise();
  test_copy_keeps_short_text_whole();
  test_copy_cuts_ascii_at_the_buffer_size();
  test_copy_never_ends_inside_a_utf8_character();
  test_show_time_counts_characters_not_bytes();
  test_no_session_tells_missing_phone_from_unsupported_phone_app();
  test_show_time_grows_with_text_length();
  test_outcomes_carry_their_show_time();
  if (failures) {
    fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  printf("flow tests passed\n");
  return 0;
}
