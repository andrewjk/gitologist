import { createHash } from "node:crypto";
import { deflateSync, inflateSync } from "node:zlib";

export interface PackObject {
	type: "commit" | "tree" | "blob" | "tag";
	sha: string;
	content: Buffer;
}

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
	const objects: PackObject[] = [];

	// Check packfile signature
	const signature = data.slice(0, 4).toString("utf-8");
	if (signature !== "PACK") {
		throw new Error("Invalid packfile signature");
	}

	const version = data.readUInt32BE(4);
	if (version !== 2) {
		throw new Error(`Unsupported packfile version: ${version}`);
	}

	const numObjects = data.readUInt32BE(8);
	let offset = 12;

	// Exclude checksum (last 20 bytes) from parsing
	const dataWithoutChecksum = data.slice(0, -20);

	for (let i = 0; i < numObjects; i++) {
		if (offset >= dataWithoutChecksum.length) {
			throw new Error("Invalid packfile: offset out of bounds");
		}

		const { type, newOffset } = parseObjectHeader(dataWithoutChecksum, offset);
		offset = newOffset;

		const { inflated, bytesConsumed } = decompressStreamData(dataWithoutChecksum, offset);

		const objectType = getObjectType(type);
		const sha = createHash("sha1")
			.update(`${objectType} ${inflated.length}\0`)
			.update(inflated)
			.digest("hex");

		objects.push({
			type: objectType,
			sha,
			content: inflated,
		});

		offset += bytesConsumed;
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

function encodeObjectHeader(type: number, size: number): Buffer {
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
