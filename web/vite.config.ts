import { defineConfig } from "vite-plus";

export default defineConfig({
	fmt: {
		ignorePatterns: ["/dist"],
		useTabs: true,
		printWidth: 100,
		sortImports: {},
		trailingComma: "all",
		overrides: [
			{
				files: ["*.json", "*.jsonc"],
				options: {
					trailingComma: "none",
				},
			},
		],
	},
	lint: {
		options: {
			typeAware: true,
			typeCheck: true,
		},
	},
	pack: {
		dts: {
			tsgo: true,
		},
		exports: true,
	},
});
