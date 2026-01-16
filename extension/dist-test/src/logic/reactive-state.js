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
    let value;
    const subscribers = new Set();
    const unsubscribe = observable.subscribe((newValue) => {
        const derivedValue = deriver(newValue);
        if (value !== derivedValue) {
            value = derivedValue;
            subscribers.forEach((sub) => sub(value));
        }
    });
    return {
        subscribe(subscriber) {
            subscribers.add(subscriber);
            subscriber(value); // Emit current value immediately
            return () => {
                subscribers.delete(subscriber);
                if (subscribers.size === 0) {
                    unsubscribe();
                }
            };
        },
        get() {
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
        let value = selector(this.state);
        const subscribers = new Set();
        this.subscribe((newState) => {
            const newValue = selector(newState);
            if (value !== newValue) {
                value = newValue;
                subscribers.forEach((sub) => sub(value));
            }
        });
        return {
            subscribe(subscriber) {
                subscribers.add(subscriber);
                subscriber(value);
                return () => subscribers.delete(subscriber);
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
