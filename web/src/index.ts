import { log } from "console";

import { add } from "./add.ts";
import { commit } from "./commit.ts";
import { IgnoreParser } from "./IgnoreParser.ts";
import { init } from "./init.ts";
import { merge } from "./merge.ts";
import { pull } from "./pull.ts";
import { push } from "./push.ts";
import { hasRemote, remoteAdd } from "./remote.ts";
import { restore } from "./restore.ts";
import { status } from "./status.ts";

export {
  add,
  commit,
  IgnoreParser,
  init,
  log,
  merge,
  pull,
  push,
  hasRemote,
  remoteAdd,
  restore,
  status,
};
