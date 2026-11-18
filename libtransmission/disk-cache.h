// This file Copyright © Mnemosyne LLC.
// It may be used under GPLv2 (SPDX: GPL-2.0-only), GPLv3 (SPDX: GPL-3.0-only),
// or any future license endorsed by Mnemosyne LLC.
// License text can be found in the licenses/ folder.

#pragma once

#ifndef __TRANSMISSION__
#error only libtransmission should #include this header.
#endif

#include <cstddef>
#include <cstdint>
#include <list>
#include <mutex>
#include <optional>
#include <span>
#include <unordered_map>
#include <vector>

#include "libtransmission/types.h"

class tr_disk_cache
{
public:
    struct Key
    {
        tr_torrent_id_t tor_id = 0;
        uint64_t byte_offset = 0;

        [[nodiscard]] bool operator==(Key const& that) const noexcept = default;
    };

    struct Entry
    {
        Key key;
        std::vector<uint8_t> data;
        bool dirty = false;
    };

    explicit tr_disk_cache(size_t mbytes = 4U);

    void set_capacity_mbytes(size_t mbytes, std::vector<Entry>& evicted_dirty);
    [[nodiscard]] size_t capacity_bytes() const noexcept;
    [[nodiscard]] size_t used_bytes() const noexcept;
    [[nodiscard]] size_t dirty_bytes() const noexcept;
    [[nodiscard]] uint64_t hits() const noexcept;
    [[nodiscard]] uint64_t misses() const noexcept;

    [[nodiscard]] bool read(tr_torrent_id_t tor_id, uint64_t byte_offset, std::span<uint8_t> setme);

    void put_clean(
        tr_torrent_id_t tor_id,
        uint64_t byte_offset,
        std::span<uint8_t const> data,
        std::vector<Entry>& evicted_dirty);

    void put_dirty(
        tr_torrent_id_t tor_id,
        uint64_t byte_offset,
        std::span<uint8_t const> data,
        std::vector<Entry>& evicted_dirty);

    void take_dirty(std::optional<tr_torrent_id_t> tor_id, std::vector<Entry>& dirty_entries);
    void invalidate_torrent(tr_torrent_id_t tor_id);
    void clear();

private:
    struct KeyHash
    {
        [[nodiscard]] size_t operator()(Key const& k) const noexcept
        {
            auto const h1 = std::hash<tr_torrent_id_t>{}(k.tor_id);
            auto const h2 = std::hash<uint64_t>{}(k.byte_offset);
            return h1 ^ (h2 + 0x9e3779b97f4a7c15ULL + (h1 << 6U) + (h1 >> 2U));
        }
    };

    void upsert(
        tr_torrent_id_t tor_id,
        uint64_t byte_offset,
        std::span<uint8_t const> data,
        bool is_dirty,
        std::vector<Entry>& evicted_dirty);

    void evict_to_limit(std::vector<Entry>& evicted_dirty);

    mutable std::mutex mutex_;
    std::list<Entry> lru_;
    std::unordered_map<Key, std::list<Entry>::iterator, KeyHash> index_;
    size_t capacity_bytes_ = 0U;
    size_t used_bytes_ = 0U;
    size_t dirty_bytes_ = 0U;
    uint64_t hits_ = 0U;
    uint64_t misses_ = 0U;
};
