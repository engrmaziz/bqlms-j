import { AsyncLocalStorage } from "node:async_hooks";

export interface RequestContextData {
	requestId: string;
	userId?: string;
}

export const requestContext = new AsyncLocalStorage<RequestContextData>();
