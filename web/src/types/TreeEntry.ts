export interface TreeEntry {
	path: string;
	sha: string;
	mode: string;
	type: "blob" | "tree";
}
