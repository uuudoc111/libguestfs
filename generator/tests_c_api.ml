(* libguestfs
 * Copyright (C) 2009-2013 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 *)

(* Please read generator/README first. *)

open Printf

open Types
open Utils
open Pr
open Docstrings
open Optgroups
open Actions
open Structs

(* Generate the tests. *)
let rec generate_tests () =
  generate_header CStyle GPLv2plus;

  pr "\
#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <fcntl.h>
#include <assert.h>

#include \"guestfs.h\"
#include \"guestfs-internal-frontend.h\"

static guestfs_h *g;

/* FIXME: nearly identical code appears in fish.c */
static void
print_strings (char *const *argv)
{
  size_t argc;

  for (argc = 0; argv[argc] != NULL; ++argc)
    printf (\"\\t%%s\\n\", argv[argc]);
}

static void
incr (guestfs_h *g, void *iv)
{
  int *i = (int *) iv;
  (*i)++;
}

/* Get md5sum of the named file. */
static void
md5sum (const char *filename, char *result)
{
  char cmd[256];
  snprintf (cmd, sizeof cmd, \"md5sum %%s\", filename);
  FILE *pp = popen (cmd, \"r\");
  if (pp == NULL) {
    perror (cmd);
    exit (EXIT_FAILURE);
  }
  if (fread (result, 1, 32, pp) != 32) {
    perror (\"md5sum: fread\");
    exit (EXIT_FAILURE);
  }
  if (pclose (pp) != 0) {
    perror (\"pclose\");
    exit (EXIT_FAILURE);
  }
  result[32] = '\\0';
}

/* Return the value for a key in a hashtable.
 * Note: the return value is part of the hash and should not be freed.
 */
static const char *
get_key (char **hash, const char *key)
{
  size_t i;

  for (i = 0; hash[i] != NULL; i += 2) {
    if (STREQ (hash[i], key))
      return hash[i+1];
  }

  return NULL; /* key not found */
}

static void
next_test (guestfs_h *g, size_t test_num, size_t nr_tests,
           const char *test_name)
{
  if (guestfs_get_verbose (g))
    printf (\"-------------------------------------------------------------------------------\\n\");
  printf (\"%%3zu/%%3zu %%s\\n\", test_num, nr_tests, test_name);
}

static void
skipped (const char *test_name, const char *fs, ...)
{
  va_list args;
  CLEANUP_FREE char *reason = NULL;
  int len;

  va_start (args, fs);
  len = vasprintf (&reason, fs, args);
  va_end (args);
  assert (len >= 0);

  printf (\"        %%s skipped (reason: %%s)\\n\",
          test_name, reason);
}

";

  (* Generate a list of commands which are not tested anywhere. *)
  pr "static void\n";
  pr "no_test_warnings (void)\n";
  pr "{\n";
  pr "  size_t i;\n";
  pr "  const char *no_tests[] = {\n";

  let hash : (string, bool) Hashtbl.t = Hashtbl.create 13 in
  List.iter (
    fun { tests = tests } ->
      let tests = filter_map (
        function
        | (_, (Always|IfAvailable _), test) -> Some test
        | (_, Disabled, _) -> None
      ) tests in
      let seq = List.concat (List.map seq_of_test tests) in
      let cmds_tested = List.map List.hd seq in
      List.iter (fun cmd -> Hashtbl.replace hash cmd true) cmds_tested
  ) all_functions;

  List.iter (
    fun { name = name } ->
      if not (Hashtbl.mem hash name) then
        pr "    \"%s\",\n" name
  ) all_functions_sorted;

  pr "    NULL\n";
  pr "  };\n";
  pr "\n";
  pr "  for (i = 0; no_tests[i] != NULL; ++i)\n";
  pr "    fprintf (stderr, \"warning: \\\"guestfs_%%s\\\" has no tests\\n\",\n";
  pr "             no_tests[i]);\n";
  pr "}\n";
  pr "\n";

  (* Generate the actual tests.  Note that we generate the tests
   * in reverse order, deliberately, so that (in general) the
   * newest tests run first.  This makes it quicker and easier to
   * debug them.
   *)
  let test_names =
    List.map (
      fun { name = name; optional = optional; tests = tests } ->
        mapi (generate_one_test name optional) tests
    ) (List.rev all_functions) in
  let test_names = List.concat test_names in
  let nr_tests = List.length test_names in

  pr "\
int
main (int argc, char *argv[])
{
  const char *filename;
  int fd;
  const size_t nr_tests = %d;
  size_t test_num = 0;
  size_t nr_failed = 0;

  setbuf (stdout, NULL);

  no_test_warnings ();

  g = guestfs_create ();
  if (g == NULL) {
    printf (\"FAIL: guestfs_create\\n\");
    exit (EXIT_FAILURE);
  }

  filename = \"test1.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, %d) == -1) {
    perror (\"ftruncate\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"FAIL: guestfs_add_drive %%s\\n\", filename);
    exit (EXIT_FAILURE);
  }

  filename = \"test2.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, %d) == -1) {
    perror (\"ftruncate\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"FAIL: guestfs_add_drive %%s\\n\", filename);
    exit (EXIT_FAILURE);
  }

  filename = \"test3.img\";
  fd = open (filename, O_WRONLY|O_CREAT|O_NOCTTY|O_TRUNC|O_CLOEXEC, 0666);
  if (fd == -1) {
    perror (filename);
    exit (EXIT_FAILURE);
  }
  if (ftruncate (fd, %d) == -1) {
    perror (\"ftruncate\");
    close (fd);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (close (fd) == -1) {
    perror (filename);
    unlink (filename);
    exit (EXIT_FAILURE);
  }
  if (guestfs_add_drive (g, filename) == -1) {
    printf (\"FAIL: guestfs_add_drive %%s\\n\", filename);
    exit (EXIT_FAILURE);
  }

  if (guestfs_add_drive_ro (g, \"../data/test.iso\") == -1) {
    printf (\"FAIL: guestfs_add_drive_ro ../data/test.iso\\n\");
    exit (EXIT_FAILURE);
  }

  /* Set a timeout in case qemu hangs during launch (RHBZ#505329). */
  alarm (600);

  if (guestfs_launch (g) == -1) {
    printf (\"FAIL: guestfs_launch\\n\");
    exit (EXIT_FAILURE);
  }

  /* Cancel previous alarm. */
  alarm (0);

  /* Create ext2 filesystem on /dev/sdb1 partition. */
  if (guestfs_part_disk (g, \"/dev/sdb\", \"mbr\") == -1) {
    printf (\"FAIL: guestfs_part_disk\\n\");
    exit (EXIT_FAILURE);
  }
  if (guestfs_mkfs (g, \"ext2\", \"/dev/sdb1\") == -1) {
    printf (\"FAIL: guestfs_mkfs (/dev/sdb1)\\n\");
    exit (EXIT_FAILURE);
  }

" nr_tests (500 * 1024 * 1024) (50 * 1024 * 1024) (10 * 1024 * 1024);

  iteri (
    fun i test_name ->
      pr "  test_num++;\n";
      pr "  next_test (g, test_num, nr_tests, \"%s\");\n" test_name;
      pr "  if (%s () == -1) {\n" test_name;
      pr "    printf (\"FAIL: %%s\\n\", \"%s\");\n" test_name;
      pr "    nr_failed++;\n";
      pr "  }\n";
  ) test_names;
  pr "\n";

  pr "  /* Check close callback is called. */
  int close_sentinel = 1;
  guestfs_set_close_callback (g, incr, &close_sentinel);

  guestfs_close (g);

  if (close_sentinel != 2) {
    fprintf (stderr, \"FAIL: close callback was not called\\n\");
    exit (EXIT_FAILURE);
  }

  unlink (\"test1.img\");
  unlink (\"test2.img\");
  unlink (\"test3.img\");

";

  pr "  if (nr_failed > 0) {\n";
  pr "    printf (\"***** %%zu / %%zu tests FAILED *****\\n\", nr_failed, nr_tests);\n";
  pr "    exit (EXIT_FAILURE);\n";
  pr "  }\n";
  pr "\n";

  pr "  exit (EXIT_SUCCESS);\n";
  pr "}\n"

and generate_one_test name optional i (init, prereq, test) =
  let test_name = sprintf "test_%s_%d" name i in

  pr "\
static int
%s_skip (void)
{
  const char *str;

  str = getenv (\"TEST_ONLY\");
  if (str)
    return strstr (str, \"%s\") == NULL;
  str = getenv (\"SKIP_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  str = getenv (\"SKIP_TEST_%s\");
  if (str && STREQ (str, \"1\")) return 1;
  return 0;
}

" test_name name (String.uppercase test_name) (String.uppercase name);

  pr "\
static int
%s (void)
{
  if (%s_skip ()) {
    skipped (\"%s\", \"environment variable set\");
    return 0;
  }

" test_name test_name test_name;

  (* Optional functions should only be tested if the relevant
   * support is available in the daemon.
   *)
  let group_test group =
    let sym = gensym "features" in
    pr "  const char *%s[] = { \"%s\", NULL };\n" sym group;
    pr "  if (!guestfs_feature_available (g, (char **) %s)) {\n" sym;
    pr "    skipped (\"%s\", \"group %%s not available in daemon\",\n"
      test_name;
    pr "             %s[0]);\n" sym;
    pr "    return 0;\n";
    pr "  }\n";
    pr "\n"
  in

  (match optional with
  | Some group -> group_test group
  | None -> ()
  );

  (match prereq with
   | Disabled ->
     pr "  skipped (\"%s\", \"test disabled in generator\");\n" test_name
   | IfAvailable group ->
     group_test group;
     generate_one_test_body name i test_name init test;
   | Always ->
     generate_one_test_body name i test_name init test
  );

  pr "  return 0;\n";
  pr "}\n";
  pr "\n";
  test_name

and generate_one_test_body name i test_name init test =
  (match init with
   | InitNone (* XXX at some point, InitNone and InitEmpty became
               * folded together as the same thing.  Really we should
               * make InitNone do nothing at all, but the tests may
               * need to be checked to make sure this is OK.
               *)
   | InitEmpty ->
       pr "  /* InitNone|InitEmpty for %s */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"]]
   | InitPartition ->
       pr "  /* InitPartition for %s: create /dev/sda1 */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"]]
   | InitGPT ->
       pr "  /* InitGPT for %s: create /dev/sda1 */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "gpt"]]
   | InitBasicFS ->
       pr "  /* InitBasicFS for %s: create ext2 on /dev/sda1 */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"];
          ["mkfs"; "ext2"; "/dev/sda1"; ""; "NOARG"; ""; ""];
          ["mount"; "/dev/sda1"; "/"]]
   | InitBasicFSonLVM ->
       pr "  /* InitBasicFSonLVM for %s: create ext2 on /dev/VG/LV */\n"
         test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["part_disk"; "/dev/sda"; "mbr"];
          ["pvcreate"; "/dev/sda1"];
          ["vgcreate"; "VG"; "/dev/sda1"];
          ["lvcreate"; "LV"; "VG"; "8"];
          ["mkfs"; "ext2"; "/dev/VG/LV"; ""; "NOARG"; ""; ""];
          ["mount"; "/dev/VG/LV"; "/"]]
   | InitISOFS ->
       pr "  /* InitISOFS for %s */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["mount_ro"; "/dev/sdd"; "/"]]
   | InitScratchFS ->
       pr "  /* InitScratchFS for %s */\n" test_name;
       List.iter (generate_test_command_call test_name)
         [["blockdev_setrw"; "/dev/sda"];
          ["umount_all"];
          ["lvm_remove_all"];
          ["mount"; "/dev/sdb1"; "/"]]
  );

  pr "\n";

  let get_seq_last = function
    | [] ->
        failwithf "%s: you cannot use [] (empty list) when expecting a command"
          test_name
    | seq ->
        let seq = List.rev seq in
        List.rev (List.tl seq), List.hd seq
  in

  match test with
  | TestRun seq ->
    pr "  /* TestRun for %s (%d) */\n" name i;
    List.iter (generate_test_command_call test_name) seq

  | TestResult (seq, expr) ->
    pr "  /* TestResult for %s (%d) */\n" name i;
    let n = List.length seq in
    iteri (
      fun i cmd ->
        let ret = if i = n-1 then "ret" else sprintf "ret%d" (n-i-1) in
        generate_test_command_call ~ret test_name cmd
    ) seq;
    pr "  if (! (%s)) {\n" expr;
    pr "    fprintf (stderr, \"%%s: test failed: expression false: %%s\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name expr;
    pr "    if (!guestfs_get_trace (g))\n";
    pr "      fprintf (stderr, \"Set LIBGUESTFS_TRACE=1 to see values returned from API calls.\\n\");\n";
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultTrue seq ->
    pr "  /* TestResultTrue for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (!ret) {\n";
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return 'true' but it returned 'false'\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name (List.hd last);
    pr "    return -1;\n";
    pr "  }\n"

  | TestResultFalse seq ->
    pr "  /* TestResultTrue for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~ret:"ret" last;
    pr "  if (ret) {\n";
    pr "    fprintf (stderr, \"%%s: test failed: expected last command %%s to return 'false' but it returned 'true'\\n\",\n";
    pr "             \"%s\", \"%s\");\n" test_name (List.hd last);
    pr "    return -1;\n";
    pr "  }\n"

  | TestLastFail seq ->
    pr "  /* TestLastFail for %s (%d) */\n" name i;
    let seq, last = get_seq_last seq in
    List.iter (generate_test_command_call test_name) seq;
    generate_test_command_call test_name ~expect_error:true last

  (* Backwards compatible ... *)

  | TestOutput (seq, expected) ->
      pr "  /* TestOutput for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (STRNEQ (%s, \"%s\")) {\n" ret (c_quote expected);
        pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", \"%s\", %s);\n" test_name (c_quote expected) ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputList (seq, expected) ->
      pr "  /* TestOutputList for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        iteri (
          fun i str ->
            pr "  if (!%s[%d]) {\n" ret i;
            pr "    fprintf (stderr, \"%%s: short list returned from command\\n\", \"%s\");\n" test_name;
            pr "    print_strings (%s);\n" ret;
            pr "    return -1;\n";
            pr "  }\n";
            pr "  if (STRNEQ (%s[%d], \"%s\")) {\n" ret i (c_quote str);
            pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", \"%s\", %s[%d]);\n" test_name (c_quote str) ret i;
            pr "    return -1;\n";
            pr "  }\n";
        ) expected;
        pr "  if (%s[%d] != NULL) {\n" ret (List.length expected);
        pr "    fprintf (stderr, \"%%s: extra elements returned from command\\n\", \"%s\");\n" test_name;
        pr "    print_strings (%s);\n" ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputListOfDevices (seq, expected) ->
      pr "  /* TestOutputListOfDevices for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        iteri (
          fun i str ->
            pr "  if (!%s[%d]) {\n" ret i;
            pr "    fprintf (stderr, \"%%s: short list returned from command\\n\", \"%s\");\n" test_name;
            pr "    print_strings (%s);\n" ret;
            pr "    return -1;\n";
            pr "  }\n";
            pr "  %s[%d][5] = 's';\n" ret i;
            pr "  if (STRNEQ (%s[%d], \"%s\")) {\n" ret i (c_quote str);
            pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", \"%s\", %s[%d]);\n" test_name (c_quote str) ret i;
            pr "    return -1;\n";
            pr "  }\n";
        ) expected;
        pr "  if (%s[%d] != NULL) {\n" ret (List.length expected);
        pr "    fprintf (stderr, \"%%s: extra elements returned from command\\n\", \"%s\");\n" test_name;
        pr "    print_strings (%s);\n" ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputInt (seq, expected) ->
      pr "  /* TestOutputInt for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (%s != %d) {\n" ret expected;
        pr "    fprintf (stderr, \"%%s: expected %d but got %%d\\n\",\n"
          expected;
        pr "             \"%s\", (int) %s);\n" test_name ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputIntOp (seq, op, expected) ->
      pr "  /* TestOutputIntOp for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (! (%s %s %d)) {\n" ret op expected;
        pr "    fprintf (stderr, \"%%s: expected %s %d but got %%d\\n\",\n"
          op expected;
        pr "             \"%s\", (int) %s);\n" test_name ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputTrue seq ->
      pr "  /* TestOutputTrue for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (!%s) {\n" ret;
        pr "    fprintf (stderr, \"%%s: expected true, got false\\n\", \"%s\");\n" test_name;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputFalse seq ->
      pr "  /* TestOutputFalse for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (%s) {\n" ret;
        pr "    fprintf (stderr, \"%%s: expected false, got true\\n\", \"%s\");\n" test_name;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputLength (seq, expected) ->
      pr "  /* TestOutputLength for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  int j;\n";
        pr "  for (j = 0; j < %d; ++j)\n" expected;
        pr "    if (%s[j] == NULL) {\n" ret;
        pr "      fprintf (stderr, \"%%s: short list returned\\n\", \"%s\");\n" test_name;
        pr "      print_strings (%s);\n" ret;
        pr "      return -1;\n";
        pr "    }\n";
        pr "  if (%s[j] != NULL) {\n" ret;
        pr "    fprintf (stderr, \"%%s: long list returned\\n\", \"%s\");\n"
          test_name;
        pr "    print_strings (%s);\n" ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputBuffer (seq, expected) ->
      pr "  /* TestOutputBuffer for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let len = String.length expected in
      let test ret =
        pr "  if (size != %d) {\n" len;
        pr "    fprintf (stderr, \"%%s: returned size of buffer wrong, expected %d but got %%zu\\n\", \"%s\", size);\n" len test_name;
        pr "    return -1;\n";
        pr "  }\n";
        pr "  if (STRNEQLEN (%s, \"%s\", size)) {\n" ret (c_quote expected);
        pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", \"%s\", %s);\n" test_name (c_quote expected) ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputStruct (seq, checks) ->
      pr "  /* TestOutputStruct for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        List.iter (
          function
          | CompareWithInt (field, expected) ->
              pr "  if (%s->%s != %d) {\n" ret field expected;
              pr "    fprintf (stderr, \"%%s: %s was %%d, expected %d\\n\",\n"
                field expected;
              pr "             \"%s\", (int) %s->%s);\n" test_name ret field;
              pr "    return -1;\n";
              pr "  }\n"
          | CompareWithIntOp (field, op, expected) ->
              pr "  if (!(%s->%s %s %d)) {\n" ret field op expected;
              pr "    fprintf (stderr, \"%%s: %s was %%d, expected %s %d\\n\",\n"
                field op expected;
              pr "             \"%s\", (int) %s->%s);\n" test_name ret field;
              pr "    return -1;\n";
              pr "  }\n"
          | CompareWithString (field, expected) ->
              pr "  if (STRNEQ (%s->%s, \"%s\")) {\n" ret field expected;
              pr "    fprintf (stderr, \"%%s: %s was \\\"%%s\\\", expected \\\"%s\\\"\\n\",\n"
                field expected;
              pr "             \"%s\", %s->%s);\n" test_name ret field;
              pr "    return -1;\n";
              pr "  }\n"
          | CompareFieldsIntEq (field1, field2) ->
              pr "  if (%s->%s != r->%s) {\n" ret field1 field2;
              pr "    fprintf (stderr, \"%s: %s (%%d) <> %s (%%d)\\n\",\n"
                test_name field1 field2;
              pr "             (int) %s->%s, (int) %s->%s);\n"
                ret field1 ret field2;
              pr "    return -1;\n";
              pr "  }\n"
          | CompareFieldsStrEq (field1, field2) ->
              pr "  if (STRNEQ (%s->%s, r->%s)) {\n" ret field1 field2;
              pr "    fprintf (stderr, \"%s: %s (\"%%s\") <> %s (\"%%s\")\\n\",\n"
                test_name field1 field2;
              pr "             %s->%s, %s->%s);\n" ret field1 ret field2;
              pr "    return -1;\n";
              pr "  }\n"
        ) checks
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputFileMD5 (seq, filename) ->
      pr "  /* TestOutputFileMD5 for %s (%d) */\n" name i;
      pr "  char expected[33];\n";
      pr "  md5sum (\"%s\", expected);\n" filename;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  if (STRNEQ (%s, expected)) {\n" ret;
        pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", expected, %s);\n" test_name ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputDevice (seq, expected) ->
      pr "  /* TestOutputDevice for %s (%d) */\n" name i;
      let seq, last = get_seq_last seq in
      let test ret =
        pr "  %s[5] = 's';\n" ret;
        pr "  if (STRNEQ (%s, \"%s\")) {\n" ret (c_quote expected);
        pr "    fprintf (stderr, \"%%s: expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", \"%s\", %s);\n" test_name (c_quote expected) ret;
        pr "    return -1;\n";
        pr "  }\n"
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last
  | TestOutputHashtable (seq, fields) ->
      pr "  /* TestOutputHashtable for %s (%d) */\n" name i;
      pr "  const char *key, *expected, *value;\n";
      let seq, last = get_seq_last seq in
      let test ret =
        List.iter (
          fun (key, value) ->
            pr "  key = \"%s\";\n" (c_quote key);
            pr "  expected = \"%s\";\n" (c_quote value);
            pr "  value = get_key (%s, key);\n" ret;
            pr "  if (value == NULL) {\n";
            pr "    fprintf (stderr, \"%%s: key \\\"%%s\\\" not found in hash: expecting \\\"%%s\\\"\\n\", \"%s\", key, expected);\n" test_name;
            pr "    return -1;\n";
            pr "  }\n";
            pr "  if (STRNEQ (value, expected)) {\n";
            pr "    fprintf (stderr, \"%%s: key \\\"%%s\\\": expected \\\"%%s\\\" but got \\\"%%s\\\"\\n\", \"%s\", key, expected, value);\n" test_name;
            pr "    return -1;\n";
            pr "  }\n";
        ) fields
      in
      List.iter (generate_test_command_call test_name) seq;
      generate_test_command_call ~test test_name last

(* Generate the code to run a command, leaving the result in the C
 * variable named 'ret'.  If you expect to get an error then you should
 * set expect_error:true.
 *)
and generate_test_command_call ?(expect_error = false) ?test ?ret test_name cmd=
  let ret = match ret with Some ret -> ret | None -> gensym "ret" in

  let name, args =
    match cmd with [] -> assert false | name :: args -> name, args in

  (* Look up the function. *)
  let f =
    try List.find (fun { name = n } -> n = name) all_functions
    with Not_found ->
      failwithf "%s: in test, command %s was not found" test_name name in

  (* Look up the arguments and return type. *)
  let style_ret, style_args, style_optargs = f.style in

  (* Match up the arguments strings and argument types. *)
  let args, optargs =
    let rec loop argts args =
      match argts, args with
      | (t::ts), (s::ss) ->
        let args, rest = loop ts ss in
        ((t, s) :: args), rest
      | [], ss -> [], ss
      | ts, [] ->
        failwithf "%s: in test, too few args given to function %s"
          test_name name
    in
    let args, optargs = loop style_args args in
    let optargs, rest = loop style_optargs optargs in
    if rest <> [] then
      failwithf "%s: in test, too many args given to function %s"
        test_name name;
    args, optargs in

  (* Generate a new symbol for each arg, and one for optargs. *)
  let args = List.map (fun (arg, value) -> arg, value, gensym "arg") args in
  let optargs_sym = gensym "optargs" in

  List.iter (
    function
    | OptString _, "NULL", _ -> ()
    | Pathname _, arg, sym
    | Device _, arg, sym
    | Mountable _, arg, sym
    | Dev_or_Path _, arg, sym
    | Mountable_or_Path _, arg, sym
    | String _, arg, sym
    | OptString _, arg, sym
    | Key _, arg, sym ->
      pr "  const char *%s = \"%s\";\n" sym (c_quote arg);
    | BufferIn _, arg, sym ->
      pr "  const char *%s = \"%s\";\n" sym (c_quote arg);
      pr "  size_t %s_size = %d;\n" sym (String.length arg)
    | Int _, _, _
    | Int64 _, _, _
    | Bool _, _, _
    | FileIn _, _, _
    | FileOut _, _, _ -> ()
    | StringList _, "", sym
    | DeviceList _, "", sym ->
      pr "  const char *const %s[1] = { NULL };\n" sym
    | StringList _, arg, sym
    | DeviceList _, arg, sym ->
      let strs = string_split " " arg in
      iteri (
        fun i str ->
          pr "  const char *%s_%d = \"%s\";\n" sym i (c_quote str);
      ) strs;
      pr "  const char *const %s[] = {\n" sym;
      iteri (
        fun i _ -> pr "    %s_%d,\n" sym i
      ) strs;
      pr "    NULL\n";
      pr "  };\n";
    | Pointer _, _, _ ->
      (* Difficult to make these pointers in order to run a test. *)
      assert false
  ) args;

  if optargs <> [] then (
    pr "  struct %s %s;\n" f.c_function optargs_sym;
    let _, bitmask = List.fold_left (
      fun (shift, bitmask) optarg ->
        let is_set =
          match optarg with
          | OBool n, "" -> false
          | OBool n, "true" ->
            pr "  %s.%s = 1;\n" optargs_sym n; true
          | OBool n, "false" ->
            pr "  %s.%s = 0;\n" optargs_sym n; true
          | OBool n, arg ->
            failwithf "boolean optional arg '%s' should be empty string or \"true\" or \"false\"" n
          | OInt n, "" -> false
          | OInt n, i ->
            let i =
              try int_of_string i
              with Failure _ -> failwithf "integer optional arg '%s' should be empty string or number" n in
            pr "  %s.%s = %d;\n" optargs_sym n i; true
          | OInt64 n, "" -> false
          | OInt64 n, i ->
            let i =
              try Int64.of_string i
              with Failure _ -> failwithf "int64 optional arg '%s' should be empty string or number" n in
            pr "  %s.%s = %Ld;\n" optargs_sym n i; true
          | OString n, "NOARG" -> false
          | OString n, arg ->
            pr "  %s.%s = \"%s\";\n" optargs_sym n (c_quote arg); true
          | OStringList n, "NOARG" -> false
          | OStringList n, "" ->
            pr "  const char *const %s[1] = { NULL };\n" n; true
          | OStringList n, arg ->
            let strs = string_split " " arg in
            iteri (
              fun i str ->
                pr "  const char *%s_%d = \"%s\";\n" n i (c_quote str);
            ) strs;
            pr "  const char *const %s[] = {\n" n;
            iteri (
              fun i _ -> pr "    %s_%d,\n" n i
            ) strs;
            pr "    NULL\n";
            pr "  };\n"; true in
        let bit = if is_set then Int64.shift_left 1L shift else 0L in
        let bitmask = Int64.logor bitmask bit in
        let shift = shift + 1 in
        (shift, bitmask)
    ) (0, 0L) optargs in
    pr "  %s.bitmask = UINT64_C(0x%Lx);\n" optargs_sym bitmask;
  );

  (match style_ret with
  | RErr | RInt _ | RBool _ -> pr "  int %s;\n" ret
  | RInt64 _ -> pr "  int64_t %s;\n" ret
  | RConstString _ | RConstOptString _ ->
    pr "  const char *%s;\n" ret
  | RString _ ->
    pr "  CLEANUP_FREE char *%s;\n" ret
  | RStringList _ | RHashtable _ ->
    pr "  CLEANUP_FREE char **%s;\n" ret;
  | RStruct (_, typ) ->
    pr "  CLEANUP_FREE_%s struct guestfs_%s *%s;\n"
      (String.uppercase typ) typ ret
  | RStructList (_, typ) ->
    pr "  CLEANUP_FREE_%s_LIST struct guestfs_%s_list *%s;\n"
      (String.uppercase typ) typ ret
  | RBufferOut _ ->
    pr "  CLEANUP_FREE char *%s;\n" ret;
    pr "  size_t size;\n"
  );

  if expect_error then
    pr "  guestfs_push_error_handler (g, NULL, NULL);\n";
  pr "  %s = %s (g" ret f.c_function;

  (* Generate the parameters. *)
  List.iter (
    function
    | OptString _, "NULL", _ -> pr ", NULL"
    | Pathname _, _, sym
    | Device _, _, sym
    | Mountable _, _, sym
    | Dev_or_Path _, _, sym
    | Mountable_or_Path _, _, sym
    | String _, _, sym
    | OptString _, _, sym
    | Key _, _, sym -> pr ", %s" sym
    | BufferIn _, _, sym -> pr ", %s, %s_size" sym sym
    | FileIn _, arg, _
    | FileOut _, arg, _ -> pr ", \"%s\"" (c_quote arg)
    | StringList _, _, sym | DeviceList _, _, sym -> pr ", (char **) %s" sym
    | Int _, arg, _ ->
      let i =
        try int_of_string arg
        with Failure "int_of_string" ->
          failwithf "%s: expecting an int, but got '%s'" test_name arg in
      pr ", %d" i
    | Int64 _, arg, _ ->
      let i =
        try Int64.of_string arg
        with Failure "int_of_string" ->
          failwithf "%s: expecting an int64, but got '%s'" test_name arg in
      pr ", %Ld" i
    | Bool _, arg, _ ->
      let b = bool_of_string arg in pr ", %d" (if b then 1 else 0)
    | Pointer _, _, _ -> assert false
  ) args;

  (match style_ret with
  | RBufferOut _ -> pr ", &size"
  | _ -> ()
  );

  if optargs <> [] then
    pr ", &%s" optargs_sym;

  pr ");\n";

  if expect_error then
    pr "  guestfs_pop_error_handler (g);\n";

  (match errcode_of_ret style_ret, expect_error with
  | `CannotReturnError, _ -> ()
  | `ErrorIsMinusOne, false ->
    pr "  if (%s == -1)\n" ret;
    pr "    return -1;\n";
  | `ErrorIsMinusOne, true ->
    pr "  if (%s != -1)\n" ret;
    pr "    return -1;\n";
  | `ErrorIsNULL, false ->
    pr "  if (%s == NULL)\n" ret;
    pr "      return -1;\n";
  | `ErrorIsNULL, true ->
    pr "  if (%s != NULL)\n" ret;
    pr "    return -1;\n";
  );

  (* Insert the test code. *)
  (match test with
  | None -> ()
  | Some f -> f ret
  )

and gensym prefix =
  sprintf "_%s%d" prefix (unique ())
