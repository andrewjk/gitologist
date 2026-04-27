export interface Credentials {
	username: string;
	token: string;
}

export interface RemoteOptions {
	credentials?: Credentials;
}
