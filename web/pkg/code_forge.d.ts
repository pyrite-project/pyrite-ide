declare namespace wasm_bindgen {
	/* tslint:disable */
	/* eslint-disable */
	/**
	* @returns {number}
	*/
	export function frb_get_rust_content_hash(): number;
	/**
	* @param {number} func_id
	* @param {any} port_
	* @param {any} ptr_
	* @param {number} rust_vec_len_
	* @param {number} data_len_
	*/
	export function frb_pde_ffi_dispatcher_primary(func_id: number, port_: any, ptr_: any, rust_vec_len_: number, data_len_: number): void;
	/**
	* @param {number} func_id
	* @param {any} ptr_
	* @param {number} rust_vec_len_
	* @param {number} data_len_
	* @returns {any}
	*/
	export function frb_pde_ffi_dispatcher_sync(func_id: number, ptr_: any, rust_vec_len_: number, data_len_: number): any;
	/**
	* @param {number} call_id
	* @param {any} ptr_
	* @param {number} rust_vec_len_
	* @param {number} data_len_
	*/
	export function frb_dart_fn_deliver_output(call_id: number, ptr_: any, rust_vec_len_: number, data_len_: number): void;
	/**
	* @param {number} ptr
	*/
	export function rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerLayoutMap(ptr: number): void;
	/**
	* @param {number} ptr
	*/
	export function rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerLayoutMap(ptr: number): void;
	/**
	* @param {number} ptr
	*/
	export function rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRopeBridge(ptr: number): void;
	/**
	* @param {number} ptr
	*/
	export function rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRopeBridge(ptr: number): void;
	/**
	* ## Safety
	* This function reclaims a raw pointer created by [`TransferClosure`], and therefore
	* should **only** be used in conjunction with it.
	* Furthermore, the WASM module in the worker must have been initialized with the shared
	* memory from the host JS scope.
	* @param {number} payload
	* @param {any[]} transfer
	*/
	export function receive_transfer_closure(payload: number, transfer: any[]): void;
	/**
	* @param {number} ptr
	* @returns {any}
	*/
	export function frb_dart_opaque_rust2dart_decode(ptr: number): any;
	/**
	* # Safety
	*
	* This should never be called manually.
	* @param {any} handle
	* @param {any} dart_handler_port
	* @returns {number}
	*/
	export function frb_dart_opaque_dart2rust_encode(handle: any, dart_handler_port: any): number;
	/**
	* @param {number} ptr
	*/
	export function frb_dart_opaque_drop_thread_box_persistent_handle(ptr: number): void;
	/**
	*/
	export function wasm_start_callback(): void;
	/**
	*/
	export class WorkerPool {
	  free(): void;
	/**
	* @param {number | undefined} [initial]
	* @param {string | undefined} [script_src]
	* @param {string | undefined} [worker_js_preamble]
	* @param {string | undefined} [wasm_bindgen_name]
	* @returns {WorkerPool}
	*/
	  static new(initial?: number, script_src?: string, worker_js_preamble?: string, wasm_bindgen_name?: string): WorkerPool;
	/**
	* Creates a new `WorkerPool` which immediately creates `initial` workers.
	*
	* The pool created here can be used over a long period of time, and it
	* will be initially primed with `initial` workers. Currently workers are
	* never released or gc'd until the whole pool is destroyed.
	*
	* # Errors
	*
	* Returns any error that may happen while a JS web worker is created and a
	* message is sent to it.
	* @param {number} initial
	* @param {string} script_src
	* @param {string} worker_js_preamble
	* @param {string} wasm_bindgen_name
	*/
	  constructor(initial: number, script_src: string, worker_js_preamble: string, wasm_bindgen_name: string);
	}
	
}

declare type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

declare interface InitOutput {
  readonly memory: WebAssembly.Memory;
  readonly frb_dart_fn_deliver_output: (a: number, b: number, c: number, d: number) => void;
  readonly frb_get_rust_content_hash: () => number;
  readonly frb_pde_ffi_dispatcher_primary: (a: number, b: number, c: number, d: number, e: number) => void;
  readonly frb_pde_ffi_dispatcher_sync: (a: number, b: number, c: number, d: number) => number;
  readonly rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerLayoutMap: (a: number) => void;
  readonly rust_arc_decrement_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRopeBridge: (a: number) => void;
  readonly rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerLayoutMap: (a: number) => void;
  readonly rust_arc_increment_strong_count_RustOpaque_flutter_rust_bridgefor_generatedRustAutoOpaqueInnerRopeBridge: (a: number) => void;
  readonly __wbg_workerpool_free: (a: number) => void;
  readonly receive_transfer_closure: (a: number, b: number, c: number, d: number) => void;
  readonly workerpool_new: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => void;
  readonly workerpool_new_raw: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => void;
  readonly frb_rust_vec_u8_free: (a: number, b: number) => void;
  readonly frb_rust_vec_u8_new: (a: number) => number;
  readonly frb_rust_vec_u8_resize: (a: number, b: number, c: number) => number;
  readonly frb_dart_opaque_rust2dart_decode: (a: number) => number;
  readonly frb_dart_opaque_dart2rust_encode: (a: number, b: number) => number;
  readonly frb_dart_opaque_drop_thread_box_persistent_handle: (a: number) => void;
  readonly wasm_start_callback: () => void;
  readonly __wbindgen_malloc: (a: number, b: number) => number;
  readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
  readonly __wbindgen_export_2: WebAssembly.Table;
  readonly _dyn_core_ed718c3d60ebd546___ops__function__FnMut_______Output______as_wasm_bindgen_348abfbd64cc0e2a___closure__WasmClosure___describe__invoke___web_sys_9d51e0c24db2936c___features__gen_MessageEvent__MessageEvent_____: (a: number, b: number, c: number) => void;
  readonly _dyn_core_ed718c3d60ebd546___ops__function__FnMut_______Output______as_wasm_bindgen_348abfbd64cc0e2a___closure__WasmClosure___describe__invoke___wasm_bindgen_348abfbd64cc0e2a___JsValue_____: (a: number, b: number, c: number) => void;
  readonly __wbindgen_add_to_stack_pointer: (a: number) => number;
  readonly __wbindgen_exn_store: (a: number) => void;
  readonly __wbindgen_free: (a: number, b: number, c: number) => void;
  readonly __wbindgen_start: () => void;
}

/**
* If `module_or_path` is {RequestInfo} or {URL}, makes a request and
* for everything else, calls `WebAssembly.instantiate` directly.
*
* @param {InitInput | Promise<InitInput>} module_or_path
*
* @returns {Promise<InitOutput>}
*/
declare function wasm_bindgen (module_or_path?: InitInput | Promise<InitInput>): Promise<InitOutput>;
