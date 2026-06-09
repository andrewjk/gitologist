import { createHash } from "node:crypto";

import { describe, it, expect } from "vite-plus/test";

import {
	createPackfile,
	parsePackfile,
	encodePktLine,
	decodePktLines,
	getObjectType,
} from "../src/packfile";
import type { PackObject } from "../src/packfile";

describe("packfile", () => {
	describe("createPackfile", () => {
		it("should create packfile with blob object", () => {
			const blobContent = Buffer.from("hello world");
			const objects: PackObject[] = [
				{
					type: "blob",
					sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
					content: blobContent,
				},
			];

			const packfile = createPackfile(objects);

			expect(packfile.slice(0, 4).toString("utf-8")).toBe("PACK");
			expect(packfile.readUInt32BE(4)).toBe(2);
			expect(packfile.readUInt32BE(8)).toBe(1);
			expect(packfile.length).toBeGreaterThan(12);
		});

		it("should create packfile with multiple objects", () => {
			const objects: PackObject[] = [
				{
					type: "blob",
					sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
					content: Buffer.from("hello world"),
				},
				{
					type: "blob",
					sha: "8d0e41234f23b8da1c8cc8e5a6d5da1b5c5e1234",
					content: Buffer.from("another file"),
				},
				{
					type: "tree",
					sha: "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
					content: Buffer.from("100644 file.txt\x00b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0"),
				},
			];

			const packfile = createPackfile(objects);

			expect(packfile.readUInt32BE(8)).toBe(3);
		});

		it("should create packfile with commit object", () => {
			const commitContent = Buffer.from(
				"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n",
			);
			const objects: PackObject[] = [
				{
					type: "commit",
					sha: "c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0",
					content: commitContent,
				},
			];

			const packfile = createPackfile(objects);

			expect(packfile.slice(0, 4).toString("utf-8")).toBe("PACK");
			expect(packfile.readUInt32BE(4)).toBe(2);
			expect(packfile.readUInt32BE(8)).toBe(1);
		});

		it("should create packfile with tag object", () => {
			const tagContent = Buffer.from(
				"object c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0\ntype commit\ntag v1.0.0\ntagger Test <test@example.com> 1234567890 +0000\n\nVersion 1.0.0\n",
			);
			const objects: PackObject[] = [
				{
					type: "tag",
					sha: "a1b2c3d4e5f6789012345678901234567890abcd",
					content: tagContent,
				},
			];

			const packfile = createPackfile(objects);

			expect(packfile.slice(0, 4).toString("utf-8")).toBe("PACK");
			expect(packfile.readUInt32BE(4)).toBe(2);
			expect(packfile.readUInt32BE(8)).toBe(1);
		});

		it("should include valid checksum at end", () => {
			const objects: PackObject[] = [
				{
					type: "blob",
					sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
					content: Buffer.from("hello world"),
				},
			];

			const packfile = createPackfile(objects);

			expect(packfile.length).toBeGreaterThan(12);
			const dataWithoutChecksum = packfile.slice(0, -20);
			const checksum = packfile.slice(-20);

			const { createHash } = require("node:crypto");
			const expectedChecksum = createHash("sha1").update(dataWithoutChecksum).digest();

			expect(checksum).toEqual(expectedChecksum);
		});
	});

	describe("parsePackfile", () => {
		it("should throw error for invalid packfile signature", () => {
			const invalidPackfile = Buffer.from("INVALID", "utf-8");

			expect(() => parsePackfile(invalidPackfile)).toThrow("Invalid packfile signature");
		});

		it("should throw error for unsupported packfile version", () => {
			const buffer = Buffer.alloc(12);
			buffer.write("PACK", 0, "utf-8");
			buffer.writeUInt32BE(99, 4);

			expect(() => parsePackfile(buffer)).toThrow("Unsupported packfile version");
		});

		it("should parse single blob object with correct SHA", () => {
			const content = Buffer.from("hello world");
			const sha = createHash("sha1")
				.update(`blob ${content.length}\0`)
				.update(content)
				.digest("hex");

			const objects: PackObject[] = [{ type: "blob", sha, content }];
			const packfile = createPackfile(objects);
			const parsed = parsePackfile(packfile);

			expect(parsed).toHaveLength(1);
			expect(parsed[0].type).toBe("blob");
			expect(parsed[0].sha).toBe(sha);
			expect(parsed[0].content).toEqual(content);
		});

		it("should parse multiple objects with correct SHAs", () => {
			const blob1 = Buffer.from("hello world");
			const blob2 = Buffer.from("another file");

			const sha1 = createHash("sha1").update(`blob ${blob1.length}\0`).update(blob1).digest("hex");
			const sha2 = createHash("sha1").update(`blob ${blob2.length}\0`).update(blob2).digest("hex");

			const objects: PackObject[] = [
				{ type: "blob", sha: sha1, content: blob1 },
				{ type: "blob", sha: sha2, content: blob2 },
			];
			const packfile = createPackfile(objects);
			const parsed = parsePackfile(packfile);

			expect(parsed).toHaveLength(2);
			expect(parsed[0].sha).toBe(sha1);
			expect(parsed[0].content).toEqual(blob1);
			expect(parsed[1].sha).toBe(sha2);
			expect(parsed[1].content).toEqual(blob2);
		});

		it("should parse commit object with correct content", () => {
			const content = Buffer.from(
				"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n",
			);
			const sha = createHash("sha1")
				.update(`commit ${content.length}\0`)
				.update(content)
				.digest("hex");

			const objects: PackObject[] = [{ type: "commit", sha, content }];
			const packfile = createPackfile(objects);
			const parsed = parsePackfile(packfile);

			expect(parsed).toHaveLength(1);
			expect(parsed[0].type).toBe("commit");
			expect(parsed[0].sha).toBe(sha);
			expect(parsed[0].content).toEqual(content);
		});

		it("should parse tree object with binary content", () => {
			const content = Buffer.from("100644 file.txt\x00b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0");
			const sha = createHash("sha1")
				.update(`tree ${content.length}\0`)
				.update(content)
				.digest("hex");

			const objects: PackObject[] = [{ type: "tree", sha, content }];
			const packfile = createPackfile(objects);
			const parsed = parsePackfile(packfile);

			expect(parsed).toHaveLength(1);
			expect(parsed[0].type).toBe("tree");
			expect(parsed[0].sha).toBe(sha);
			expect(parsed[0].content).toEqual(content);
		});
	});

	describe("encodePktLine and decodePktLines", () => {
		it("should encode and decode pkt-line", () => {
			const line = "hello world";
			const encoded = encodePktLine(line);
			const decoded = decodePktLines(encoded);

			expect(decoded).toEqual([line]);
		});

		it("should encode and decode null pkt-line", () => {
			const encoded = encodePktLine(null);
			const decoded = decodePktLines(encoded);

			expect(decoded).toEqual([""]);
		});

		it("should encode and decode multiple pkt-lines", () => {
			const lines = ["first line", "second line", "third line"];
			const encoded = Buffer.concat(lines.map(encodePktLine));
			const decoded = decodePktLines(encoded);

			expect(decoded).toEqual(lines);
		});

		it("should handle empty string pkt-line", () => {
			const line = "";
			const encoded = encodePktLine(line);
			const decoded = decodePktLines(encoded);

			expect(decoded).toEqual([""]);
		});
	});

	describe("getObjectType", () => {
		it("should return correct type for commit", () => {
			expect(getObjectType(1)).toBe("commit");
		});

		it("should return correct type for tree", () => {
			expect(getObjectType(2)).toBe("tree");
		});

		it("should return correct type for blob", () => {
			expect(getObjectType(3)).toBe("blob");
		});

		it("should return correct type for tag", () => {
			expect(getObjectType(4)).toBe("tag");
		});

		it("should throw error for unknown type", () => {
			expect(() => getObjectType(99)).toThrow("Unknown object type");
		});
	});
});
