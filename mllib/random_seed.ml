(* virt-sysprep
 * Copyright (C) 2012-2013 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

let set_random_seed (g : Guestfs.guestfs) root =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    let files = [
      "/var/lib/random-seed"; (* Fedora *)
      "/var/lib/urandom/random-seed"; (* Debian *)
      "/var/lib/misc/random-seed"; (* SuSE *)
    ] in
    List.iter (
      fun file ->
        if g#is_file file then (
          (* Get 8 bytes of randomness from the host. *)
          let chan = open_in "/dev/urandom" in
          let buf = String.create 8 in
          really_input chan buf 0 8;
          close_in chan;

          g#write file buf
        )
    ) files;
    true
  )
  else
    false
