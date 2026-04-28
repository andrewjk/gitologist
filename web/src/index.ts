import { log } from "console";

import { add } from "./add.ts";
import { commit } from "./commit.ts";
import { IgnoreParser } from "./IgnoreParser.ts";
import { init } from "./init.ts";
import { merge } from "./merge.ts";
import { pull } from "./pull.ts";
import { push, setUpstreamBranch } from "./push.ts";
import { hasRemote, remoteAdd } from "./remote.ts";
import { restore } from "./restore.ts";
import { stash, unstash } from "./stash.ts";
import { status } from "./status.ts";
export type { FetchResult } from "./types/FetchResult.ts";
export type { RemoteOptions } from "./types/RemoteOptions.ts";

export {
	add,
	commit,
	IgnoreParser,
	init,
	log,
	merge,
	pull,
	push,
	setUpstreamBranch,
	hasRemote,
	remoteAdd,
	restore,
	stash,
	status,
	unstash,
};
