export interface MergeResult {
	success: boolean;
	fastForward: boolean;
	commitSha?: string;
	message?: string;
}
