// This file Copyright © Mnemosyne LLC.
// It may be used under GPLv2 (SPDX: GPL-2.0-only), GPLv3 (SPDX: GPL-3.0-only),
// or any future license endorsed by Mnemosyne LLC.
// License text can be found in the licenses/ folder.

#include <algorithm>
#include <iterator>
#include <utility>

#include "libtransmission/disk-cache.h"

namespace
{
constexpr size_t BytesPerMiB = 1024ULL * 1024ULL;
}

tr_disk_cache::tr_disk_cache(size_t const mbytes)
    : capacity_bytes_{ mbytes * BytesPerMiB }
{
}

void tr_disk_cache::set_capacity_mbytes(size_t const mbytes, std::vector<Entry>& evicted_dirty)
{
    auto lock = std::lock_guard{ mutex_ };
    capacity_bytes_ = mbytes * BytesPerMiB;
    evict_to_limit(evicted_dirty);
}

size_t tr_disk_cache::capacity_bytes() const noexcept
{
    auto lock = std::lock_guard{ mutex_ };
    return capacity_bytes_;
}

size_t tr_disk_cache::used_bytes() const noexcept
{
    auto lock = std::lock_guard{ mutex_ };
    return used_bytes_;
}

size_t tr_disk_cache::dirty_bytes() const noexcept
{
    auto lock = std::lock_guard{ mutex_ };
    return dirty_bytes_;
}

uint64_t tr_disk_cache::hits() const noexcept
{
    auto lock = std::lock_guard{ mutex_ };
    return hits_;
}

uint64_t tr_disk_cache::misses() const noexcept
{
    auto lock = std::lock_guard{ mutex_ };
    return misses_;
}

bool tr_disk_cache::read(tr_torrent_id_t const tor_id, uint64_t const byte_offset, std::span<uint8_t> const setme)
{
    auto lock = std::lock_guard{ mutex_ };
    if (capacity_bytes_ == 0U)
    {
        return false;
    }

    auto const it = index_.find(Key{ tor_id, byte_offset });
    if (it == std::end(index_))
    {
        ++misses_;
        return false;
    }

    auto& entry = *it->second;
    if (std::size(entry.data) != std::size(setme))
    {
        ++misses_;
        return false;
    }

    std::copy_n(std::data(entry.data), std::size(setme), std::data(setme));
    lru_.splice(std::begin(lru_), lru_, it->second);
    ++hits_;
    return true;
}

void tr_disk_cache::put_clean(
    tr_torrent_id_t const tor_id,
    uint64_t const byte_offset,
    std::span<uint8_t const> const data,
    std::vector<Entry>& evicted_dirty)
{
    upsert(tor_id, byte_offset, data, false, evicted_dirty);
}

void tr_disk_cache::put_dirty(
    tr_torrent_id_t const tor_id,
    uint64_t const byte_offset,
    std::span<uint8_t const> const data,
    std::vector<Entry>& evicted_dirty)
{
    upsert(tor_id, byte_offset, data, true, evicted_dirty);
}

void tr_disk_cache::upsert(
    tr_torrent_id_t const tor_id,
    uint64_t const byte_offset,
    std::span<uint8_t const> const data,
    bool const is_dirty,
    std::vector<Entry>& evicted_dirty)
{
    auto lock = std::lock_guard{ mutex_ };
    if (capacity_bytes_ == 0U || std::empty(data))
    {
        return;
    }

    auto const key = Key{ tor_id, byte_offset };
    if (auto const it = index_.find(key); it != std::end(index_))
    {
        auto& entry = *it->second;
        // Preserve newer uncommitted dirty RAM data over a clean read-miss fill
        if (entry.dirty && !is_dirty)
        {
            lru_.splice(std::begin(lru_), lru_, it->second);
            return;
        }

        auto const old_size = std::size(entry.data);
        auto const new_size = std::size(data);
        entry.data.assign(std::begin(data), std::end(data));
        used_bytes_ = used_bytes_ - old_size + new_size;
        if (entry.dirty)
        {
            dirty_bytes_ = dirty_bytes_ - old_size + new_size;
        }
        else if (is_dirty)
        {
            entry.dirty = true;
            dirty_bytes_ += new_size;
        }
        lru_.splice(std::begin(lru_), lru_, it->second);
    }
    else
    {
        auto const sz = std::size(data);
        lru_.push_front(Entry{ key, std::vector<uint8_t>{ std::begin(data), std::end(data) }, is_dirty });
        index_.emplace(key, std::begin(lru_));
        used_bytes_ += sz;
        if (is_dirty)
        {
            dirty_bytes_ += sz;
        }
    }

    evict_to_limit(evicted_dirty);
}

void tr_disk_cache::evict_to_limit(std::vector<Entry>& evicted_dirty)
{
    while (used_bytes_ > capacity_bytes_ && !std::empty(lru_))
    {
        auto last_it = std::prev(std::end(lru_));
        auto const sz = std::size(last_it->data);
        used_bytes_ -= sz;
        if (last_it->dirty)
        {
            dirty_bytes_ -= sz;
            evicted_dirty.push_back(std::move(*last_it));
        }
        index_.erase(last_it->key);
        lru_.erase(last_it);
    }
}

void tr_disk_cache::take_dirty(std::optional<tr_torrent_id_t> const tor_id, std::vector<Entry>& dirty_entries)
{
    auto lock = std::lock_guard{ mutex_ };
    for (auto& entry : lru_)
    {
        if (entry.dirty && (!tor_id || entry.key.tor_id == *tor_id))
        {
            dirty_entries.push_back(Entry{ entry.key, entry.data, true });
            entry.dirty = false;
            dirty_bytes_ -= std::size(entry.data);
        }
    }
}

void tr_disk_cache::invalidate_torrent(tr_torrent_id_t const tor_id)
{
    auto lock = std::lock_guard{ mutex_ };
    for (auto it = std::begin(lru_); it != std::end(lru_);)
    {
        if (it->key.tor_id == tor_id)
        {
            auto const sz = std::size(it->data);
            used_bytes_ -= sz;
            if (it->dirty)
            {
                dirty_bytes_ -= sz;
            }
            index_.erase(it->key);
            it = lru_.erase(it);
        }
        else
        {
            ++it;
        }
    }
}

void tr_disk_cache::clear()
{
    auto lock = std::lock_guard{ mutex_ };
    index_.clear();
    lru_.clear();
    used_bytes_ = 0U;
    dirty_bytes_ = 0U;
}
