export interface Ref {
	name: string;
	sha: string;
}

export interface FetchResult {
	remote: string;
	refs: Ref[];
}
