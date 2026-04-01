export interface StatusInfo {
	branch: string;
	upToDate: string;
	staged: string[];
	modified: string[];
	untracked: string[];
}
