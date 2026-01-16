// Reactive state management inspired by praxis framework
// Provides observable state updates for extension UI components

/**
 * Subscription callback type
 */
export type Subscriber<T> = (value: T) => void;

/**
 * Unsubscribe function
 */
export type Unsubscriber = () => void;

/**
 * Observable interface (similar to Svelte stores and praxis reactive engine)
 */
export interface Observable<T> {
  subscribe(subscriber: Subscriber<T>): Unsubscriber;
  get(): T;
}

/**
 * Writable observable interface
 */
export interface WritableObservable<T> extends Observable<T> {
  set(value: T): void;
  update(updater: (value: T) => T): void;
}

/**
 * Create a writable observable (similar to Svelte writable stores)
 */
export function writable<T>(initialValue: T): WritableObservable<T> {
  let value = initialValue;
  const subscribers = new Set<Subscriber<T>>();

  return {
    subscribe(subscriber: Subscriber<T>): Unsubscriber {
      subscribers.add(subscriber);
      subscriber(value); // Emit current value immediately

      return () => {
        subscribers.delete(subscriber);
      };
    },

    get(): T {
      return value;
    },

    set(newValue: T): void {
      if (value !== newValue) {
        value = newValue;
        subscribers.forEach((sub) => sub(value));
      }
    },

    update(updater: (value: T) => T): void {
      this.set(updater(value));
    },
  };
}

/**
 * Create a derived observable (computed value)
 */
export function derived<T, U>(
  observable: Observable<T>,
  deriver: (value: T) => U
): Observable<U> {
  let value: U = deriver(observable.get());
  let initialized = false;
  const subscribers = new Set<Subscriber<U>>();
  let sourceUnsubscribe: Unsubscriber | null = null;

  return {
    subscribe(subscriber: Subscriber<U>): Unsubscriber {
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

    get(): U {
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
export class ReactiveState<T extends object> {
  private state: T;
  private subscribers = new Set<Subscriber<T>>();
  private updateQueue: Array<(state: T) => void> = [];
  private isProcessing = false;

  constructor(initialState: T) {
    this.state = initialState;
  }

  /**
   * Subscribe to state changes
   */
  subscribe(subscriber: Subscriber<T>): Unsubscriber {
    this.subscribers.add(subscriber);
    subscriber(this.state); // Emit current value immediately

    return () => {
      this.subscribers.delete(subscriber);
    };
  }

  /**
   * Get current state (immutable)
   */
  get(): Readonly<T> {
    return this.state;
  }

  /**
   * Apply mutation to state (batched)
   */
  apply(mutator: (state: T) => void): void {
    this.updateQueue.push(mutator);
    this.processQueue();
  }

  /**
   * Apply multiple mutations atomically
   */
  batch(mutators: Array<(state: T) => void>): void {
    this.updateQueue.push(...mutators);
    this.processQueue();
  }

  /**
   * Process update queue (batched for performance)
   */
  private processQueue(): void {
    if (this.isProcessing) return;

    this.isProcessing = true;

    // Apply all pending mutations
    while (this.updateQueue.length > 0) {
      const mutator = this.updateQueue.shift()!;
      mutator(this.state);
    }

    // Notify subscribers once after all mutations
    this.subscribers.forEach((sub) => sub(this.state));

    this.isProcessing = false;
  }

  /**
   * Create a derived observable from state
   */
  derive<U>(selector: (state: T) => U): Observable<U> {
    // Current derived value
    let value: U = selector(this.state);
    // Subscribers to the derived observable
    const subscribers = new Set<Subscriber<U>>();
    // Unsubscribe function for the parent subscription (when active)
    let parentUnsubscribe: Unsubscriber | null = null;

    const start = () => {
      if (parentUnsubscribe) return;
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
      subscribe(subscriber: Subscriber<U>): Unsubscriber {
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
      get(): U {
        return value;
      },
    };
  }
}

/**
 * Create a reactive state container
 */
export function createReactiveState<T extends object>(
  initialState: T
): ReactiveState<T> {
  return new ReactiveState(initialState);
}
