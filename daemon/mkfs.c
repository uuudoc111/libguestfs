/* libguestfs - the guestfsd daemon
 * Copyright (C) 2009 Red Hat Inc.
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
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <sys/stat.h>

#include "daemon.h"
#include "actions.h"

#define MAX_ARGS 16

/* Takes optional arguments, consult optargs_bitmask. */
int
do_mkfs_opts (const char *fstype, const char *device, int blocksize)
{
  const char *argv[MAX_ARGS];
  size_t i = 0, j;
  char blocksize_str[32];
  int r;
  char *err;

  argv[i++] = "mkfs";
  argv[i++] = "-t";
  argv[i++] = fstype;

  /* mkfs.ntfs requires the -Q argument otherwise it writes zeroes
   * to every block and does bad block detection, neither of which
   * are useful behaviour for virtual devices.
   */
  if (STREQ (fstype, "ntfs"))
    argv[i++] = "-Q";

  /* mkfs.reiserfs produces annoying interactive prompts unless you
   * tell it to be quiet.
   */
  if (STREQ (fstype, "reiserfs"))
    argv[i++] = "-f";

  /* Same for JFS. */
  if (STREQ (fstype, "jfs"))
    argv[i++] = "-f";

  /* For GFS, GFS2, assume a single node. */
  if (STREQ (fstype, "gfs") || STREQ (fstype, "gfs2")) {
    argv[i++] = "-p";
    argv[i++] = "lock_nolock";
    /* The man page says this is default, but it doesn't seem to be: */
    argv[i++] = "-j";
    argv[i++] = "1";
    /* Don't ask questions: */
    argv[i++] = "-O";
  }

  /* Process blocksize parameter if set. */
  if (optargs_bitmask & GUESTFS_MKFS_OPTS_BLOCKSIZE_BITMASK) {
    if (blocksize <= 0 || !is_power_of_2 (blocksize)) {
      reply_with_error ("block size must be > 0 and a power of 2");
      return -1;
    }

    if (STREQ (fstype, "vfat") ||
        STREQ (fstype, "msdos")) {
      /* For VFAT map the blocksize into a cluster size.  However we
       * have to determine the block device sector size in order to do
       * this.
       */
      int sectorsize = do_blockdev_getss (device);
      if (sectorsize == -1)
        return -1;

      int sectors_per_cluster = blocksize / sectorsize;
      if (sectors_per_cluster < 1 || sectors_per_cluster > 128) {
        reply_with_error ("unsupported cluster size for %s filesystem (requested cluster size = %d, sector size = %d, trying sectors per cluster = %d)",
                          fstype, blocksize, sectorsize, sectors_per_cluster);
        return -1;
      }

      snprintf (blocksize_str, sizeof blocksize_str, "%d", sectors_per_cluster);
      argv[i++] = "-s";
      argv[i++] = blocksize_str;
    }
    else if (STREQ (fstype, "ntfs")) {
      /* For NTFS map the blocksize into a cluster size. */
      snprintf (blocksize_str, sizeof blocksize_str, "%d", blocksize);
      argv[i++] = "-c";
      argv[i++] = blocksize_str;
    }
    else {
      /* For all other filesystem types, try the -b option. */
      snprintf (blocksize_str, sizeof blocksize_str, "%d", blocksize);
      argv[i++] = "-b";
      argv[i++] = blocksize_str;
    }
  }

  argv[i++] = device;
  argv[i++] = NULL;

  if (i > MAX_ARGS)
    abort ();

  r = commandv (NULL, &err, argv);
  if (r == -1) {
    reply_with_error ("%s: %s: %s", fstype, device, err);
    free (err);
    return -1;
  }

  free (err);
  return 0;
}

int
do_mkfs (const char *fstype, const char *device)
{
  optargs_bitmask = 0;
  return do_mkfs_opts (fstype, device, 0);
}

int
do_mkfs_b (const char *fstype, int blocksize, const char *device)
{
  optargs_bitmask = GUESTFS_MKFS_OPTS_BLOCKSIZE_BITMASK;
  return do_mkfs_opts (fstype, device, blocksize);
}
