export interface IndexEntry {
	path: string;
	sha: string;
	mode: string;
	size: number;
	ctimeSeconds: number;
	ctimeNanos: number;
	mtimeSeconds: number;
	mtimeNanos: number;
	dev: number;
	ino: number;
	uid: number;
	gid: number;
}
