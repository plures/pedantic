"use strict";
// Reactive state management inspired by praxis framework
// Provides observable state updates for extension UI components
Object.defineProperty(exports, "__esModule", { value: true });
exports.ReactiveState = void 0;
exports.writable = writable;
exports.derived = derived;
exports.createReactiveState = createReactiveState;
/**
 * Create a writable observable (similar to Svelte writable stores)
 */
function writable(initialValue) {
    let value = initialValue;
    const subscribers = new Set();
    return {
        subscribe(subscriber) {
            subscribers.add(subscriber);
            subscriber(value); // Emit current value immediately
            return () => {
                subscribers.delete(subscriber);
            };
        },
        get() {
            return value;
        },
        set(newValue) {
            if (value !== newValue) {
                value = newValue;
                subscribers.forEach((sub) => sub(value));
            }
        },
        update(updater) {
            this.set(updater(value));
        },
    };
}
/**
 * Create a derived observable (computed value)
 */
function derived(observable, deriver) {
    let value = deriver(observable.get());
    let initialized = false;
    const subscribers = new Set();
    let sourceUnsubscribe = null;
    return {
        subscribe(subscriber) {
            // Lazily subscribe to the source observable when the first subscriber appears
            if (subscribers.size === 0) {
                // Initialize the derived value from the current source value
                const initial = deriver(observable.get());
                value = initial;
                initialized = true;
                // Keep derived value in sync with source updates
                sourceUnsubscribe = observable.subscribe((newValue) => {
                    const derivedValue = deriver(newValue);
                    if (!initialized || value !== derivedValue) {
                        value = derivedValue;
                        initialized = true;
                        subscribers.forEach((sub) => sub(value));
                    }
                });
            }
            subscribers.add(subscriber);
            // Emit current value immediately (if initialized)
            if (initialized) {
                subscriber(value);
            }
            return () => {
                subscribers.delete(subscriber);
                if (subscribers.size === 0 && sourceUnsubscribe) {
                    sourceUnsubscribe();
                    sourceUnsubscribe = null;
                }
            };
        },
        get() {
            if (!initialized) {
                // Ensure get() returns a meaningful value even before any subscription
                const initial = deriver(observable.get());
                value = initial;
                initialized = true;
            }
            return value;
        },
    };
}
/**
 * Reactive state container with batched updates
 */
class ReactiveState {
    state;
    subscribers = new Set();
    updateQueue = [];
    isProcessing = false;
    constructor(initialState) {
        this.state = initialState;
    }
    /**
     * Subscribe to state changes
     */
    subscribe(subscriber) {
        this.subscribers.add(subscriber);
        subscriber(this.state); // Emit current value immediately
        return () => {
            this.subscribers.delete(subscriber);
        };
    }
    /**
     * Get current state (immutable)
     */
    get() {
        return this.state;
    }
    /**
     * Apply mutation to state (batched)
     */
    apply(mutator) {
        this.updateQueue.push(mutator);
        this.processQueue();
    }
    /**
     * Apply multiple mutations atomically
     */
    batch(mutators) {
        this.updateQueue.push(...mutators);
        this.processQueue();
    }
    /**
     * Process update queue (batched for performance)
     */
    processQueue() {
        if (this.isProcessing)
            return;
        this.isProcessing = true;
        // Apply all pending mutations
        while (this.updateQueue.length > 0) {
            const mutator = this.updateQueue.shift();
            mutator(this.state);
        }
        // Notify subscribers once after all mutations
        this.subscribers.forEach((sub) => sub(this.state));
        this.isProcessing = false;
    }
    /**
     * Create a derived observable from state
     */
    derive(selector) {
        // Current derived value
        let value = selector(this.state);
        // Subscribers to the derived observable
        const subscribers = new Set();
        // Unsubscribe function for the parent subscription (when active)
        let parentUnsubscribe = null;
        const start = () => {
            if (parentUnsubscribe)
                return;
            parentUnsubscribe = this.subscribe((newState) => {
                const newValue = selector(newState);
                if (value !== newValue) {
                    value = newValue;
                    subscribers.forEach((sub) => sub(value));
                }
            });
        };
        const stop = () => {
            if (parentUnsubscribe) {
                parentUnsubscribe();
                parentUnsubscribe = null;
            }
        };
        return {
            subscribe(subscriber) {
                // If this is the first subscriber, make sure we are observing the parent
                if (subscribers.size === 0) {
                    // Recompute from current parent state in case it changed while idle
                    value = selector(this.state);
                    start();
                }
                subscribers.add(subscriber);
                // Emit current derived value immediately
                subscriber(value);
                return () => {
                    subscribers.delete(subscriber);
                    // If no more subscribers, detach from the parent to avoid leaks
                    if (subscribers.size === 0) {
                        stop();
                    }
                };
            },
            get() {
                return value;
            },
        };
    }
}
exports.ReactiveState = ReactiveState;
/**
 * Create a reactive state container
 */
function createReactiveState(initialState) {
    return new ReactiveState(initialState);
}
