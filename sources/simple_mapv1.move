/// This module provides a solution for sorted maps, that is it has the properties that
/// 1) Keys point to Values
/// 2) Each Key must be unique
/// 3) A Key can be found within O(N) time
/// 4) The keys are unsorted.
/// 5) Adds and removals take O(N) time
module dat3::simple_mapv1 {
    use std::error;
    use std::option;
    use std::vector;

    /// Map key already exists
    const EKEY_ALREADY_EXISTS: u64 = 1;
    /// Map key is not found
    const EKEY_NOT_FOUND: u64 = 2;

    struct SimpleMapV1<Key, Value> has copy, drop, store {
        data: vector<Element<Key, Value>>,
    }

    struct Element<Key, Value> has copy, drop, store {
        key: Key,
        value: Value,
    }

    public fun length<Key: store, Value: store>(map: &SimpleMapV1<Key, Value>): u64 {
        vector::length(&map.data)
    }

    public fun create<Key: store, Value: store>(): SimpleMapV1<Key, Value> {
        SimpleMapV1 {
            data: vector::empty(),
        }
    }

    public fun borrow<Key: store, Value: store>(
        map: &SimpleMapV1<Key, Value>,
        key: &Key,
    ): &Value {
        let maybe_idx = find(map, key);
        assert!(option::is_some(&maybe_idx), error::invalid_argument(EKEY_NOT_FOUND));
        let idx = option::extract(&mut maybe_idx);
        &vector::borrow(&map.data, idx).value
    }

    public fun borrow_mut<Key: store, Value: store>(
        map: &mut SimpleMapV1<Key, Value>,
        key: &Key,
    ): &mut Value {
        let maybe_idx = find(map, key);
        assert!(option::is_some(&maybe_idx), error::invalid_argument(EKEY_NOT_FOUND));
        let idx = option::extract(&mut maybe_idx);
        &mut vector::borrow_mut(&mut map.data, idx).value
    }

    public fun contains_key<Key: store, Value: store>(
        map: &SimpleMapV1<Key, Value>,
        key: &Key,
    ): bool {
        let maybe_idx = find(map, key);
        option::is_some(&maybe_idx)
    }

    public fun destroy_empty<Key: store, Value: store>(map: SimpleMapV1<Key, Value>) {
        let SimpleMapV1 { data } = map;
        vector::destroy_empty(data);
    }

    public fun add<Key: store, Value: store>(
        map: &mut SimpleMapV1<Key, Value>,
        key: Key,
        value: Value,
    ) {
        let maybe_idx = find(map, &key);
        assert!(option::is_none(&maybe_idx), error::invalid_argument(EKEY_ALREADY_EXISTS));

        vector::push_back(&mut map.data, Element { key, value });
    }

    public fun remove<Key: store, Value: store>(
        map: &mut SimpleMapV1<Key, Value>,
        key: &Key,
    ): (Key, Value) {
        let maybe_idx = find(map, key);
        assert!(option::is_some(&maybe_idx), error::invalid_argument(EKEY_NOT_FOUND));
        let placement = option::extract(&mut maybe_idx);
        let Element { key, value } = vector::swap_remove(&mut map.data, placement);
        (key, value)
    }

    fun find<Key: store, Value: store>(
        map: &SimpleMapV1<Key, Value>,
        key: &Key,
    ): option::Option<u64> {
        let leng = vector::length(&map.data);
        let i = 0;
        while (i < leng) {
            let element = vector::borrow(&map.data, i);
            if (&element.key == key) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none<u64>()
    }

    public fun find_index<Key: store, Value: store>(
        map: &SimpleMapV1<Key, Value>
        , i: u64
    ): (&Key, &Value) {
        let element = vector::borrow(&map.data, i);
        (&element.key, &element.value)
    }

    public fun find_index_mut<Key: store, Value: store>(
        map: &mut  SimpleMapV1<Key, Value>,
        i: u64,
    ): (&Key, &mut Value) {
        let element = vector::borrow_mut( &mut map.data, i);
        (&element.key, &mut element.value)
    }

    #[test]
    public fun add_remove_many() {
        let map = create<u64, u64>();

        assert!(length(&map) == 0, 0);
        assert!(!contains_key(&map, &3), 1);
        add(&mut map, 3, 1);
        assert!(length(&map) == 1, 2);
        assert!(contains_key(&map, &3), 3);
        assert!(borrow(&map, &3) == &1, 4);
        *borrow_mut(&mut map, &3) = 2;
        assert!(borrow(&map, &3) == &2, 5);

        assert!(!contains_key(&map, &2), 6);
        add(&mut map, 2, 5);
        assert!(length(&map) == 2, 7);
        assert!(contains_key(&map, &2), 8);
        assert!(borrow(&map, &2) == &5, 9);
        *borrow_mut(&mut map, &2) = 9;
        assert!(borrow(&map, &2) == &9, 10);

        remove(&mut map, &2);
        assert!(length(&map) == 1, 11);
        assert!(!contains_key(&map, &2), 12);
        assert!(borrow(&map, &3) == &2, 13);

        remove(&mut map, &3);
        assert!(length(&map) == 0, 14);
        assert!(!contains_key(&map, &3), 15);

        destroy_empty(map);
    }

    #[test]
    #[expected_failure]
    public fun add_twice() {
        let map = create<u64, u64>();
        add(&mut map, 3, 1);
        add(&mut map, 3, 1);

        remove(&mut map, &3);
        destroy_empty(map);
    }

    #[test]
    #[expected_failure]
    public fun remove_twice() {
        let map = create<u64, u64>();
        add(&mut map, 3, 1);
        remove(&mut map, &3);
        remove(&mut map, &3);

        destroy_empty(map);
    }
}
