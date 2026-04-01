export interface LogEntry {
	sha: string;
	abbreviatedSha: string;
	tree: string;
	parent: string | null;
	author: string;
	committer: string;
	date: Date;
	message: string;
}
