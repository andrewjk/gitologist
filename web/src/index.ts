import { log } from "console";

import { add } from "./add.ts";
import { getCurrentBranch, getCurrentCommit } from "./branch.ts";
import { commit } from "./commit.ts";
import { fetchOrigin } from "./fetch.ts";
import { IgnoreParser } from "./IgnoreParser.ts";
import { init } from "./init.ts";
import { merge } from "./merge.ts";
import { pull } from "./pull.ts";
import { push, setUpstreamBranch } from "./push.ts";
import { getRemoteUrl, hasRemote, remoteAdd, setRemoteUrl } from "./remote.ts";
import { restore } from "./restore.ts";
import { show } from "./show.ts";
import { stash, unstash } from "./stash.ts";
import { status } from "./status.ts";
import { switchBranch } from "./switch.ts";
export type { FetchResult } from "./types/FetchResult.ts";
export type { RemoteOptions } from "./types/RemoteOptions.ts";

export {
	add,
	commit,
	fetchOrigin,
	getCurrentBranch,
	getCurrentCommit,
	getRemoteUrl,
	IgnoreParser,
	init,
	log,
	merge,
	pull,
	push,
	setUpstreamBranch,
	hasRemote,
	remoteAdd,
	setRemoteUrl,
	restore,
	show,
	stash,
	status,
	switchBranch,
	unstash,
};
