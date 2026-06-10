import { createHash } from "node:crypto";
import { deflateSync, inflateSync } from "node:zlib";

export interface PackObject {
	type: "commit" | "tree" | "blob" | "tag";
	sha: string;
	content: Buffer;
}

type PackEntryType =
	| { kind: "object"; type: PackObject["type"] }
	| { kind: "ofsDelta"; offset: number }
	| { kind: "refDelta"; baseSha: string };

export function encodePktLine(line: string | null): Buffer {
	if (line === null) {
		return Buffer.from("0000", "utf-8");
	}
	const length = Buffer.byteLength(line, "utf-8") + 4;
	const hexLength = length.toString(16).padStart(4, "0");
	if (length === 4) {
		return Buffer.from(hexLength, "utf-8");
	}
	return Buffer.from(hexLength + line, "utf-8");
}

export function decodePktLines(data: Buffer): string[] {
	const lines: string[] = [];
	let offset = 0;

	while (offset < data.length) {
		const hexLength = data.slice(offset, offset + 4).toString("utf-8");
		if (hexLength === "0000") {
			lines.push("");
			offset += 4;
			continue;
		}

		const length = parseInt(hexLength, 16);
		if (length === 0 || length > data.length - offset) {
			break;
		}

		const line = data.slice(offset + 4, offset + length).toString("utf-8");
		lines.push(line);
		offset += length;
	}

	return lines;
}

export function parsePackfile(data: Buffer): PackObject[] {
	const signature = data.slice(0, 4).toString("utf-8");
	if (signature !== "PACK") {
		throw new Error("Invalid packfile signature");
	}

	const version = data.readUInt32BE(4);
	if (version !== 2) {
		throw new Error(`Unsupported packfile version: ${version}`);
	}

	const numObjects = data.readUInt32BE(8);

	const dataWithoutChecksum = data.slice(0, -20);

	interface RawPackEntry {
		entryType: PackEntryType;
		content: Buffer;
		packOffset: number;
	}

	const rawEntries: RawPackEntry[] = [];
	const offsetToIndex = new Map<number, number>();
	let offset = 12;

	for (let i = 0; i < numObjects; i++) {
		if (offset >= dataWithoutChecksum.length) {
			throw new Error("Invalid packfile: offset out of bounds");
		}

		const { type, newOffset: headerEndOffset } = parseObjectHeader(dataWithoutChecksum, offset);

		const entryTypeResult = parsePackEntryType(type, dataWithoutChecksum, headerEndOffset);
		if (!entryTypeResult) {
			throw new Error("Invalid packfile: unknown entry type");
		}
		const { entryType, dataOffset } = entryTypeResult;

		const { inflated, bytesConsumed } = decompressStreamData(dataWithoutChecksum, dataOffset);

		rawEntries.push({ entryType, content: inflated, packOffset: offset });
		offsetToIndex.set(offset, rawEntries.length - 1);
		offset = dataOffset + bytesConsumed;
	}

	type ResolvedEntry = { content: Buffer; type: PackObject["type"] };
	const resolved = new Map<number, ResolvedEntry>();

	function resolveEntry(index: number): ResolvedEntry {
		if (resolved.has(index)) return resolved.get(index)!;
		const entry = rawEntries[index];
		let content: Buffer;
		let objType: PackObject["type"];

		switch (entry.entryType.kind) {
			case "object":
				content = entry.content;
				objType = entry.entryType.type;
				break;
			case "ofsDelta": {
				const basePackOffset = entry.packOffset - entry.entryType.offset;
				const baseIndex = offsetToIndex.get(basePackOffset)!;
				const base = resolveEntry(baseIndex);
				content = applyDelta(base.content, entry.content);
				objType = base.type;
				break;
			}
			case "refDelta": {
				let baseIndex: number | undefined;
				for (let j = 0; j < rawEntries.length; j++) {
					const raw = rawEntries[j];
					if (raw.entryType.kind !== "object") continue;
					const header = `${raw.entryType.type} ${raw.content.length}\0`;
					const sha = createHash("sha1").update(header).update(raw.content).digest("hex");
					if (sha === entry.entryType.baseSha) {
						baseIndex = j;
						break;
					}
				}
				const base = resolveEntry(baseIndex!);
				content = applyDelta(base.content, entry.content);
				objType = base.type;
				break;
			}
		}

		const result = { content, type: objType };
		resolved.set(index, result);
		return result;
	}

	const objects: PackObject[] = [];

	for (let i = 0; i < rawEntries.length; i++) {
		const entry = rawEntries[i];
		let content: Buffer;
		let objectType: PackObject["type"];

		if (entry.entryType.kind === "object") {
			objectType = entry.entryType.type;
			content = entry.content;
		} else {
			const resolvedResult = resolveEntry(i);
			content = resolvedResult.content;
			objectType = resolvedResult.type;
		}

		const sha = createHash("sha1")
			.update(`${objectType} ${content.length}\0`)
			.update(content)
			.digest("hex");

		objects.push({ type: objectType, sha, content });
	}

	return objects;
}

function parseObjectHeader(
	data: Buffer,
	offset: number,
): { type: number; size: number; newOffset: number } {
	let byte = data[offset];
	const type = (byte >> 4) & 0x07;
	let size = byte & 0x0f;
	let shift = 4;
	let currentOffset = offset + 1;

	while (byte & 0x80) {
		byte = data[currentOffset];
		size |= (byte & 0x7f) << shift;
		shift += 7;
		currentOffset++;
	}

	return { type, size, newOffset: currentOffset };
}

function parsePackEntryType(
	typeNum: number,
	data: Buffer,
	offset: number,
): { entryType: PackEntryType; dataOffset: number } | null {
	switch (typeNum) {
		case 1:
			return { entryType: { kind: "object", type: "commit" }, dataOffset: offset };
		case 2:
			return { entryType: { kind: "object", type: "tree" }, dataOffset: offset };
		case 3:
			return { entryType: { kind: "object", type: "blob" }, dataOffset: offset };
		case 4:
			return { entryType: { kind: "object", type: "tag" }, dataOffset: offset };
		case 6: {
			let off = offset;
			let byte = data[off];
			off++;
			let negOffset = byte & 0x7f;
			while (byte & 0x80) {
				byte = data[off];
				off++;
				negOffset = ((negOffset + 1) << 7) | (byte & 0x7f);
			}
			return { entryType: { kind: "ofsDelta", offset: negOffset }, dataOffset: off };
		}
		case 7: {
			if (offset + 20 > data.length) return null;
			const sha = data.slice(offset, offset + 20).toString("hex");
			return { entryType: { kind: "refDelta", baseSha: sha }, dataOffset: offset + 20 };
		}
		default:
			return null;
	}
}

function decompressStreamData(
	data: Buffer,
	offset: number,
): { inflated: Buffer; bytesConsumed: number } {
	const remainingData = data.slice(offset);
	const inflated = inflateSync(remainingData);

	// Find the exact compressed length using binary search
	let lo = 1;
	let hi = remainingData.length;
	while (lo < hi) {
		const mid = Math.floor((lo + hi) / 2);
		try {
			const test = inflateSync(remainingData.slice(0, mid));
			if (test.length === inflated.length && test.equals(inflated)) {
				hi = mid;
			} else {
				lo = mid + 1;
			}
		} catch {
			lo = mid + 1;
		}
	}

	return { inflated, bytesConsumed: lo };
}

function applyDelta(base: Buffer, delta: Buffer): Buffer {
	let deltaOffset = 0;

	function readSize(): number {
		let size = 0;
		let shift = 0;
		while (deltaOffset < delta.length) {
			const byte = delta[deltaOffset];
			deltaOffset++;
			size |= (byte & 0x7f) << shift;
			shift += 7;
			if ((byte & 0x80) === 0) break;
		}
		return size;
	}

	readSize();
	readSize();

	const parts: Buffer[] = [];

	while (deltaOffset < delta.length) {
		const cmd = delta[deltaOffset];
		deltaOffset++;

		if (cmd & 0x80) {
			let copyOffset = 0;
			let copySize = 0;

			if (cmd & 0x01) {
				copyOffset = delta[deltaOffset];
				deltaOffset++;
			}
			if (cmd & 0x02) {
				copyOffset |= delta[deltaOffset] << 8;
				deltaOffset++;
			}
			if (cmd & 0x04) {
				copyOffset |= delta[deltaOffset] << 16;
				deltaOffset++;
			}
			if (cmd & 0x08) {
				copyOffset |= delta[deltaOffset] << 24;
				deltaOffset++;
			}

			if (cmd & 0x10) {
				copySize = delta[deltaOffset];
				deltaOffset++;
			}
			if (cmd & 0x20) {
				copySize |= delta[deltaOffset] << 8;
				deltaOffset++;
			}
			if (cmd & 0x40) {
				copySize |= delta[deltaOffset] << 16;
				deltaOffset++;
			}

			if (copySize === 0) copySize = 0x10000;

			parts.push(base.slice(copyOffset, copyOffset + copySize));
		} else if (cmd > 0) {
			parts.push(delta.slice(deltaOffset, deltaOffset + cmd));
			deltaOffset += cmd;
		}
	}

	return Buffer.concat(parts);
}

const OBJECT_TYPES: Record<number, PackObject["type"]> = {
	1: "commit",
	2: "tree",
	3: "blob",
	4: "tag",
};

export function getObjectType(typeNum: number): PackObject["type"] {
	const type = OBJECT_TYPES[typeNum];
	if (!type) {
		throw new Error(`Unknown object type: ${typeNum}`);
	}
	return type;
}

export function createPackfile(objects: PackObject[]): Buffer {
	const version = Buffer.alloc(4);
	version.writeUInt32BE(2, 0);

	const numObjects = Buffer.alloc(4);
	numObjects.writeUInt32BE(objects.length, 0);

	const objectBuffers: Buffer[] = [];

	for (const obj of objects) {
		const typeNum = getTypeNumber(obj.type);
		const header = encodeObjectHeader(typeNum, obj.content.length);
		const compressed = deflateSync(obj.content);
		objectBuffers.push(Buffer.concat([header, compressed]));
	}

	const packfile = Buffer.concat([
		Buffer.from("PACK", "utf-8"),
		version,
		numObjects,
		...objectBuffers,
	]);

	// Add checksum
	const checksum = createHash("sha1").update(packfile).digest();

	return Buffer.concat([packfile, checksum]);
}

function getTypeNumber(type: PackObject["type"]): number {
	const types: Record<PackObject["type"], number> = {
		commit: 1,
		tree: 2,
		blob: 3,
		tag: 4,
	};
	return types[type];
}

export function encodeObjectHeader(type: number, size: number): Buffer {
	const bytes: number[] = [];
	let byte = (type << 4) | (size & 0x0f);
	size >>= 4;

	while (size > 0) {
		bytes.push(byte | 0x80);
		byte = size & 0x7f;
		size >>= 7;
	}

	bytes.push(byte);

	return Buffer.from(bytes);
}
