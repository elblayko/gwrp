-- ========================================================
-- GridRP (GRID) - Production MariaDB Schema
-- Database Architecture: 100% Stored Procedures & Analytical Views
-- Engine: InnoDB | Standard: MariaDB 10.6+ / 11.x
-- ========================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- --------------------------------------------------------
-- 1. Table Structures
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS grid_players (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    money BIGINT NOT NULL DEFAULT 1000,
    respect INT NOT NULL DEFAULT 0,
    gang VARCHAR(32) NOT NULL DEFAULT '',
    job VARCHAR(32) NOT NULL DEFAULT 'citizen',
    level INT NOT NULL DEFAULT 1,
    xp BIGINT NOT NULL DEFAULT 0,
    last_seen INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_players_gang (gang),
    INDEX idx_players_job (job)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_gangs (
    name VARCHAR(32) NOT NULL PRIMARY KEY,
    leader_steamid VARCHAR(20) NOT NULL,
    bank BIGINT NOT NULL DEFAULT 0,
    respect INT NOT NULL DEFAULT 0,
    created_at INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_gangs_leader (leader_steamid),
    INDEX idx_gangs_respect (respect DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_gang_members (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    gang VARCHAR(32) NOT NULL,
    rank VARCHAR(16) NOT NULL DEFAULT 'member',
    joined_at INT UNSIGNED NOT NULL DEFAULT 0,
    INDEX idx_members_gang (gang),
    CONSTRAINT fk_grid_gang_members FOREIGN KEY (gang) REFERENCES grid_gangs(name) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_inventory (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    steamid VARCHAR(20) NOT NULL,
    bag_index TINYINT UNSIGNED NOT NULL DEFAULT 0,
    slot_index TINYINT UNSIGNED NOT NULL DEFAULT 1,
    item_id VARCHAR(64) NOT NULL,
    item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
    amount INT NOT NULL DEFAULT 1,
    item_data JSON NULL,
    INDEX idx_inventory_steamid (steamid, bag_index, slot_index),
    INDEX idx_inventory_item (steamid, item_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_player_bags (
    steamid VARCHAR(20) NOT NULL PRIMARY KEY,
    bag1 VARCHAR(64) NOT NULL DEFAULT '',
    bag2 VARCHAR(64) NOT NULL DEFAULT '',
    bag3 VARCHAR(64) NOT NULL DEFAULT '',
    bag4 VARCHAR(64) NOT NULL DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_turfs (
    map VARCHAR(64) NOT NULL,
    turf_id INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    pos_x DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    pos_y DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    pos_z DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    radius INT NOT NULL DEFAULT 450,
    owner VARCHAR(32) NOT NULL DEFAULT 'neutral',
    tax_rate TINYINT UNSIGNED NOT NULL DEFAULT 10,
    PRIMARY KEY (map, turf_id),
    INDEX idx_turfs_owner (owner)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_settings (
    `key` VARCHAR(64) NOT NULL PRIMARY KEY,
    `val` TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_player_buffs (
    steamid VARCHAR(20) NOT NULL,
    buff_id VARCHAR(32) NOT NULL,
    duration DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    remaining DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    stacks TINYINT UNSIGNED NOT NULL DEFAULT 1,
    applied_at INT UNSIGNED NOT NULL DEFAULT 0,
    expires_at_unix INT UNSIGNED NOT NULL DEFAULT 0,
    data JSON NULL,
    PRIMARY KEY (steamid, buff_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Auction House Tables
CREATE TABLE IF NOT EXISTS grid_auctions (
    auction_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    seller_steamid VARCHAR(20) NOT NULL,
    seller_name VARCHAR(64) NOT NULL,
    item_id VARCHAR(64) NOT NULL,
    item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
    amount INT UNSIGNED NOT NULL DEFAULT 1,
    item_data JSON NULL,
    start_bid BIGINT UNSIGNED NOT NULL,
    current_bid BIGINT UNSIGNED NOT NULL DEFAULT 0,
    high_bidder_steamid VARCHAR(20) NULL,
    high_bidder_name VARCHAR(64) NULL,
    buyout_price BIGINT UNSIGNED NOT NULL DEFAULT 0,
    deposit_amount BIGINT UNSIGNED NOT NULL DEFAULT 0,
    status ENUM('ACTIVE', 'SOLD', 'EXPIRED', 'CANCELLED') NOT NULL DEFAULT 'ACTIVE',
    duration_hours TINYINT UNSIGNED NOT NULL DEFAULT 24,
    created_at_unix INT UNSIGNED NOT NULL,
    expires_at_unix INT UNSIGNED NOT NULL,
    closed_at_unix INT UNSIGNED NULL,
    INDEX idx_auction_status_expires (status, expires_at_unix),
    INDEX idx_auction_item (item_id, status),
    INDEX idx_auction_seller (seller_steamid, status),
    INDEX idx_auction_bidder (high_bidder_steamid, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS grid_auction_collection (
    collection_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    steamid VARCHAR(20) NOT NULL,
    item_id VARCHAR(64) NOT NULL,
    item_type VARCHAR(32) NOT NULL DEFAULT 'generic',
    amount INT UNSIGNED NOT NULL DEFAULT 1,
    item_data JSON NULL,
    source_reason ENUM('WON_AUCTION', 'EXPIRED_AUCTION', 'CANCELLED_AUCTION') NOT NULL,
    source_auction_id BIGINT UNSIGNED NOT NULL,
    created_at_unix INT UNSIGNED NOT NULL,
    claimed TINYINT(1) NOT NULL DEFAULT 0,
    claimed_at_unix INT UNSIGNED NULL,
    INDEX idx_collection_claim (steamid, claimed)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- High-Performance Telemetry Table (Compound B-Trees + Monthly Range Partitioning)
CREATE TABLE IF NOT EXISTS grid_telemetry (
    log_id BIGINT UNSIGNED AUTO_INCREMENT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    unix_ts INT UNSIGNED NOT NULL DEFAULT (UNIX_TIMESTAMP()),
    category ENUM('ECONOMY', 'PLAYER_ACTION', 'ANTIDEBUG', 'COMBAT', 'TRADE') NOT NULL,
    action_type VARCHAR(48) NOT NULL,
    actor_steamid VARCHAR(20) NOT NULL,
    target_steamid VARCHAR(20) NULL,
    numeric_value DECIMAL(12, 2) NOT NULL DEFAULT 0.00,
    metadata JSON NULL,
    PRIMARY KEY (log_id, unix_ts),
    INDEX idx_actor_time (actor_steamid, created_at),
    INDEX idx_category_action_time (category, action_type, created_at),
    INDEX idx_target_time (target_steamid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
PARTITION BY RANGE (unix_ts) (
    PARTITION p_2026_10 VALUES LESS THAN (1761955200),
    PARTITION p_2026_11 VALUES LESS THAN (1764547200),
    PARTITION p_2026_12 VALUES LESS THAN (1767225600),
    PARTITION p_2027_01 VALUES LESS THAN (1769904000),
    PARTITION p_future  VALUES LESS THAN MAXVALUE
);

-- Persistent Map Entities
CREATE TABLE IF NOT EXISTS grid_map_entities (
    spawn_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    map_name VARCHAR(64) NOT NULL,
    class_name VARCHAR(64) NOT NULL,
    pos_x FLOAT NOT NULL,
    pos_y FLOAT NOT NULL,
    pos_z FLOAT NOT NULL,
    ang_p FLOAT NOT NULL,
    ang_y FLOAT NOT NULL,
    ang_r FLOAT NOT NULL,
    placed_by VARCHAR(20) NOT NULL,
    custom_data JSON DEFAULT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_map_name (map_name)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- --------------------------------------------------------
-- 2. Analytical & Dashboard Views (100% Analytical Reads)
-- --------------------------------------------------------

CREATE OR REPLACE VIEW v_player_profile AS
SELECT
    p.steamid,
    p.name,
    p.money,
    p.respect,
    p.gang,
    p.job,
    p.level,
    p.xp,
    p.last_seen,
    m.rank AS gang_rank
FROM grid_players p
LEFT JOIN grid_gang_members m ON p.steamid = m.steamid;

CREATE OR REPLACE VIEW v_player_inventory AS
SELECT
    id,
    steamid,
    bag_index,
    slot_index,
    item_id,
    item_type,
    amount,
    item_data
FROM grid_inventory;

CREATE OR REPLACE VIEW v_player_bags AS
SELECT
    steamid,
    bag1,
    bag2,
    bag3,
    bag4
FROM grid_player_bags;

CREATE OR REPLACE VIEW v_player_buffs AS
SELECT
    steamid,
    buff_id,
    duration,
    remaining,
    stacks,
    applied_at,
    expires_at_unix,
    data
FROM grid_player_buffs;

CREATE OR REPLACE VIEW v_gang_leaderboard AS
SELECT
    g.name,
    g.leader_steamid,
    p.name AS leader_name,
    g.bank,
    g.respect,
    g.created_at,
    COUNT(DISTINCT m.steamid) AS member_count,
    COUNT(DISTINCT t.turf_id) AS turf_count
FROM grid_gangs g
LEFT JOIN grid_players p ON g.leader_steamid = p.steamid
LEFT JOIN grid_gang_members m ON g.name = m.gang
LEFT JOIN grid_turfs t ON g.name = t.owner
GROUP BY g.name, g.leader_steamid, p.name, g.bank, g.respect, g.created_at
ORDER BY g.respect DESC, g.bank DESC;

CREATE OR REPLACE VIEW v_gang_roster AS
SELECT
    m.gang,
    m.steamid,
    m.rank,
    m.joined_at,
    p.name,
    p.money,
    p.job,
    p.level,
    p.last_seen
FROM grid_gang_members m
LEFT JOIN grid_players p ON m.steamid = p.steamid
ORDER BY
    CASE m.rank WHEN 'leader' THEN 1 WHEN 'officer' THEN 2 ELSE 3 END,
    m.joined_at ASC;

CREATE OR REPLACE VIEW v_map_turfs AS
SELECT
    map,
    turf_id,
    name,
    pos_x,
    pos_y,
    pos_z,
    radius,
    owner,
    tax_rate
FROM grid_turfs
ORDER BY turf_id ASC;

CREATE OR REPLACE VIEW v_settings AS
SELECT `key`, `val` FROM grid_settings;

CREATE OR REPLACE VIEW v_economy_metrics AS
SELECT
    category,
    action_type,
    COUNT(*) AS event_count,
    SUM(numeric_value) AS total_volume,
    AVG(numeric_value) AS average_volume,
    MIN(created_at) AS earliest_record,
    MAX(created_at) AS latest_record
FROM grid_telemetry
WHERE category IN ('ECONOMY', 'TRADE')
GROUP BY category, action_type;

CREATE OR REPLACE VIEW v_player_audit_history AS
SELECT
    log_id,
    created_at,
    category,
    action_type,
    actor_steamid,
    target_steamid,
    numeric_value,
    metadata
FROM grid_telemetry
ORDER BY created_at DESC;

CREATE OR REPLACE VIEW v_combat_telemetry AS
SELECT
    action_type AS weapon_class,
    COUNT(*) AS total_skirmishes,
    SUM(numeric_value) AS total_damage_dealt,
    AVG(numeric_value) AS avg_damage_per_engagement
FROM grid_telemetry
WHERE category = 'COMBAT'
GROUP BY action_type;

-- Streamlined Market Statistics View per Base Item
CREATE OR REPLACE VIEW v_auction_metrics AS
SELECT 
    a.item_id,
    MIN(CASE WHEN a.status = 'ACTIVE' AND a.buyout_price > 0 THEN a.buyout_price ELSE NULL END) AS min_active_buyout,
    COUNT(CASE WHEN a.status = 'ACTIVE' THEN 1 ELSE NULL END) AS active_listings_count,
    ROUND(AVG(CASE 
        WHEN a.status = 'SOLD' 
         AND a.closed_at_unix >= (UNIX_TIMESTAMP() - 604800) 
        THEN GREATEST(a.current_bid, a.buyout_price) 
        ELSE NULL 
    END)) AS avg_sale_price_7d,
    COALESCE(SUM(CASE 
        WHEN a.status = 'SOLD' 
         AND a.closed_at_unix >= (UNIX_TIMESTAMP() - 86400) 
        THEN a.amount 
        ELSE 0 
    END), 0) AS sold_volume_24h
FROM grid_auctions a
GROUP BY a.item_id;

CREATE OR REPLACE VIEW v_grid_map_spawns AS
SELECT spawn_id, map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data
FROM grid_map_entities;

-- --------------------------------------------------------
-- 3. Stored Procedures (100% Writes via MariaDB Procedures)
-- --------------------------------------------------------

DELIMITER $$

-- Telemetry Logging Procedure
CREATE OR REPLACE PROCEDURE grid_log_telemetry(
    IN p_category VARCHAR(20),
    IN p_action_type VARCHAR(48),
    IN p_actor_steamid VARCHAR(20),
    IN p_target_steamid VARCHAR(20),
    IN p_numeric_value DECIMAL(12, 2),
    IN p_metadata JSON
)
BEGIN
    INSERT INTO grid_telemetry (
        unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata
    ) VALUES (
        UNIX_TIMESTAMP(), p_category, p_action_type, p_actor_steamid, p_target_steamid, p_numeric_value, p_metadata
    );
END$$

-- Player Management Procedures
CREATE OR REPLACE PROCEDURE grid_upsert_player(
    IN p_steamid VARCHAR(20),
    IN p_name VARCHAR(64),
    IN p_money BIGINT,
    IN p_respect INT,
    IN p_gang VARCHAR(32),
    IN p_job VARCHAR(32),
    IN p_level INT,
    IN p_xp BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    INSERT INTO grid_players (steamid, name, money, respect, gang, job, level, xp, last_seen)
    VALUES (p_steamid, p_name, p_money, p_respect, p_gang, p_job, p_level, p_xp, p_last_seen)
    ON DUPLICATE KEY UPDATE
        name = p_name,
        money = p_money,
        respect = p_respect,
        gang = p_gang,
        job = p_job,
        level = p_level,
        xp = p_xp,
        last_seen = p_last_seen;
END$$

CREATE OR REPLACE PROCEDURE grid_update_player_money(
    IN p_steamid VARCHAR(20),
    IN p_money BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE grid_players
    SET money = p_money, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE OR REPLACE PROCEDURE grid_update_player_gang(
    IN p_steamid VARCHAR(20),
    IN p_gang VARCHAR(32),
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE grid_players
    SET gang = p_gang, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE OR REPLACE PROCEDURE grid_update_player_job(
    IN p_steamid VARCHAR(20),
    IN p_job VARCHAR(32),
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE grid_players
    SET job = p_job, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

CREATE OR REPLACE PROCEDURE grid_update_player_level_xp(
    IN p_steamid VARCHAR(20),
    IN p_level INT,
    IN p_xp BIGINT,
    IN p_last_seen INT UNSIGNED
)
BEGIN
    UPDATE grid_players
    SET level = p_level, xp = p_xp, last_seen = p_last_seen
    WHERE steamid = p_steamid;
END$$

-- Gangs & Atomic Vault Transfers
CREATE OR REPLACE PROCEDURE grid_create_gang(
    IN p_gang_name VARCHAR(32),
    IN p_leader_steamid VARCHAR(20),
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO grid_gangs (name, leader_steamid, bank, respect, created_at)
    VALUES (p_gang_name, p_leader_steamid, 0, 0, p_unix_time)
    ON DUPLICATE KEY UPDATE leader_steamid = p_leader_steamid;

    INSERT INTO grid_gang_members (steamid, gang, rank, joined_at)
    VALUES (p_leader_steamid, p_gang_name, 'leader', p_unix_time)
    ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = 'leader';

    UPDATE grid_players
    SET gang = p_gang_name, last_seen = p_unix_time
    WHERE steamid = p_leader_steamid;

    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE grid_add_gang_member(
    IN p_steamid VARCHAR(20),
    IN p_gang_name VARCHAR(32),
    IN p_rank VARCHAR(16),
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO grid_gang_members (steamid, gang, rank, joined_at)
    VALUES (p_steamid, p_gang_name, p_rank, p_unix_time)
    ON DUPLICATE KEY UPDATE gang = p_gang_name, rank = p_rank;

    UPDATE grid_players
    SET gang = p_gang_name, last_seen = p_unix_time
    WHERE steamid = p_steamid;

    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE grid_remove_gang_member(
    IN p_steamid VARCHAR(20)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    DELETE FROM grid_gang_members WHERE steamid = p_steamid;
    UPDATE grid_players SET gang = '' WHERE steamid = p_steamid;

    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE grid_add_gang_bank(
    IN p_gang_name VARCHAR(32),
    IN p_amount BIGINT
)
BEGIN
    UPDATE grid_gangs
    SET bank = GREATEST(0, bank + p_amount)
    WHERE name = p_gang_name;
END$$

CREATE OR REPLACE PROCEDURE grid_transfer_gang_vault(
    IN p_steamid VARCHAR(20),
    IN p_gang_name VARCHAR(32),
    IN p_delta BIGINT,
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE v_player_money BIGINT DEFAULT 0;
    DECLARE v_gang_bank BIGINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT money INTO v_player_money FROM grid_players WHERE steamid = p_steamid FOR UPDATE;
    SELECT bank INTO v_gang_bank FROM grid_gangs WHERE name = p_gang_name FOR UPDATE;

    -- p_delta > 0: Deposit from player wallet into gang bank
    -- p_delta < 0: Withdrawal from gang bank into player wallet
    IF (p_delta > 0 AND v_player_money >= p_delta) THEN
        UPDATE grid_players SET money = money - p_delta, last_seen = p_unix_time WHERE steamid = p_steamid;
        UPDATE grid_gangs SET bank = bank + p_delta WHERE name = p_gang_name;
    ELSEIF (p_delta < 0 AND v_gang_bank >= ABS(p_delta)) THEN
        UPDATE grid_players SET money = money + ABS(p_delta), last_seen = p_unix_time WHERE steamid = p_steamid;
        UPDATE grid_gangs SET bank = bank - ABS(p_delta) WHERE name = p_gang_name;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient balance for gang vault transaction';
    END IF;

    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE grid_disband_gang(
    IN p_gang_name VARCHAR(32)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE grid_players SET gang = '' WHERE gang = p_gang_name;
    DELETE FROM grid_gang_members WHERE gang = p_gang_name;
    DELETE FROM grid_gangs WHERE name = p_gang_name;

    COMMIT;
END$$

-- Inventory & Bag Storage Procedures
CREATE OR REPLACE PROCEDURE grid_set_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_bag_index TINYINT UNSIGNED,
    IN p_slot_index TINYINT UNSIGNED,
    IN p_item_id VARCHAR(64),
    IN p_item_type VARCHAR(32),
    IN p_amount INT,
    IN p_item_data JSON
)
BEGIN
    DELETE FROM grid_inventory
    WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;

    IF p_amount > 0 THEN
        INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data)
        VALUES (p_steamid, p_bag_index, p_slot_index, p_item_id, p_item_type, p_amount, p_item_data);
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_delete_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_bag_index TINYINT UNSIGNED,
    IN p_slot_index TINYINT UNSIGNED
)
BEGIN
    DELETE FROM grid_inventory
    WHERE steamid = p_steamid AND bag_index = p_bag_index AND slot_index = p_slot_index;
END$$

CREATE OR REPLACE PROCEDURE grid_move_inventory_slot(
    IN p_steamid VARCHAR(20),
    IN p_from_bag TINYINT UNSIGNED,
    IN p_from_slot TINYINT UNSIGNED,
    IN p_to_bag TINYINT UNSIGNED,
    IN p_to_slot TINYINT UNSIGNED
)
BEGIN
    DECLARE v_src_id BIGINT UNSIGNED;
    DECLARE v_src_item VARCHAR(64);
    DECLARE v_src_type VARCHAR(32);
    DECLARE v_src_amt INT;
    DECLARE v_src_data JSON;

    DECLARE v_dst_id BIGINT UNSIGNED;
    DECLARE v_dst_item VARCHAR(64);
    DECLARE v_dst_type VARCHAR(32);
    DECLARE v_dst_amt INT;
    DECLARE v_dst_data JSON;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT id, item_id, item_type, amount, item_data
    INTO v_src_id, v_src_item, v_src_type, v_src_amt, v_src_data
    FROM grid_inventory
    WHERE steamid = p_steamid AND bag_index = p_from_bag AND slot_index = p_from_slot
    FOR UPDATE;

    IF v_src_id IS NOT NULL THEN
        SELECT id, item_id, item_type, amount, item_data
        INTO v_dst_id, v_dst_item, v_dst_type, v_dst_amt, v_dst_data
        FROM grid_inventory
        WHERE steamid = p_steamid AND bag_index = p_to_bag AND slot_index = p_to_slot
        FOR UPDATE;

        IF v_dst_id IS NULL THEN
            UPDATE grid_inventory
            SET bag_index = p_to_bag, slot_index = p_to_slot
            WHERE id = v_src_id;
        ELSEIF v_src_item = v_dst_item THEN
            -- Combine identical item stacks
            UPDATE grid_inventory SET amount = amount + v_src_amt WHERE id = v_dst_id;
            DELETE FROM grid_inventory WHERE id = v_src_id;
        ELSE
            -- Swap slots
            UPDATE grid_inventory SET bag_index = p_to_bag, slot_index = p_to_slot WHERE id = v_src_id;
            UPDATE grid_inventory SET bag_index = p_from_bag, slot_index = p_from_slot WHERE id = v_dst_id;
        END IF;
    END IF;

    COMMIT;
END$$

CREATE OR REPLACE PROCEDURE grid_set_player_bags(
    IN p_steamid VARCHAR(20),
    IN p_bag1 VARCHAR(64),
    IN p_bag2 VARCHAR(64),
    IN p_bag3 VARCHAR(64),
    IN p_bag4 VARCHAR(64)
)
BEGIN
    INSERT INTO grid_player_bags (steamid, bag1, bag2, bag3, bag4)
    VALUES (p_steamid, p_bag1, p_bag2, p_bag3, p_bag4)
    ON DUPLICATE KEY UPDATE
        bag1 = p_bag1,
        bag2 = p_bag2,
        bag3 = p_bag3,
        bag4 = p_bag4;
END$$

-- Turf & Territory Procedures
CREATE OR REPLACE PROCEDURE grid_save_map_turf(
    IN p_map VARCHAR(64),
    IN p_turf_id INT,
    IN p_name VARCHAR(64),
    IN p_pos_x DECIMAL(10, 2),
    IN p_pos_y DECIMAL(10, 2),
    IN p_pos_z DECIMAL(10, 2),
    IN p_radius INT,
    IN p_owner VARCHAR(32),
    IN p_tax_rate TINYINT UNSIGNED
)
BEGIN
    INSERT INTO grid_turfs (map, turf_id, name, pos_x, pos_y, pos_z, radius, owner, tax_rate)
    VALUES (p_map, p_turf_id, p_name, p_pos_x, p_pos_y, p_pos_z, p_radius, p_owner, p_tax_rate)
    ON DUPLICATE KEY UPDATE
        name = p_name,
        pos_x = p_pos_x,
        pos_y = p_pos_y,
        pos_z = p_pos_z,
        radius = p_radius,
        owner = p_owner,
        tax_rate = p_tax_rate;
END$$

CREATE OR REPLACE PROCEDURE grid_clear_map_turfs(
    IN p_map VARCHAR(64)
)
BEGIN
    DELETE FROM grid_turfs WHERE map = p_map;
END$$

CREATE OR REPLACE PROCEDURE grid_delete_map_turf(
    IN p_map VARCHAR(64),
    IN p_turf_id INT
)
BEGIN
    DELETE FROM grid_turfs WHERE map = p_map AND turf_id = p_turf_id;
END$$

CREATE OR REPLACE PROCEDURE grid_set_turf_tax(
    IN p_map VARCHAR(64),
    IN p_turf_id INT,
    IN p_tax_rate TINYINT UNSIGNED
)
BEGIN
    UPDATE grid_turfs
    SET tax_rate = p_tax_rate
    WHERE map = p_map AND turf_id = p_turf_id;
END$$

-- Atomic Economy & Protection Tax Collection
CREATE OR REPLACE PROCEDURE grid_collect_printer_taxed(
    IN p_actor_steamid VARCHAR(20),
    IN p_controlling_gang VARCHAR(32),
    IN p_payout_amount BIGINT,
    IN p_tax_amount BIGINT,
    IN p_unix_time INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE grid_players
    SET money = money + p_payout_amount, last_seen = p_unix_time
    WHERE steamid = p_actor_steamid;

    IF p_tax_amount > 0 AND p_controlling_gang != '' AND p_controlling_gang != 'neutral' AND p_controlling_gang != 'Police' THEN
        UPDATE grid_gangs
        SET bank = bank + p_tax_amount
        WHERE name = p_controlling_gang;
    END IF;

    COMMIT;
END$$

-- Player Buff Procedures
CREATE OR REPLACE PROCEDURE grid_save_player_buff(
    IN p_steamid VARCHAR(20),
    IN p_buff_id VARCHAR(32),
    IN p_duration DECIMAL(10, 2),
    IN p_remaining DECIMAL(10, 2),
    IN p_stacks TINYINT UNSIGNED,
    IN p_applied_at INT UNSIGNED,
    IN p_expires_at_unix INT UNSIGNED,
    IN p_data JSON
)
BEGIN
    INSERT INTO grid_player_buffs (
        steamid, buff_id, duration, remaining, stacks, applied_at, expires_at_unix, data
    ) VALUES (
        p_steamid, p_buff_id, p_duration, p_remaining, p_stacks, p_applied_at, p_expires_at_unix, p_data
    ) ON DUPLICATE KEY UPDATE
        duration = p_duration,
        remaining = p_remaining,
        stacks = p_stacks,
        applied_at = p_applied_at,
        expires_at_unix = p_expires_at_unix,
        data = p_data;
END$$

CREATE OR REPLACE PROCEDURE grid_delete_player_buff(
    IN p_steamid VARCHAR(20),
    IN p_buff_id VARCHAR(32)
)
BEGIN
    DELETE FROM grid_player_buffs
    WHERE steamid = p_steamid AND buff_id = p_buff_id;
END$$

CREATE OR REPLACE PROCEDURE grid_clear_player_buffs(
    IN p_steamid VARCHAR(20)
)
BEGIN
    DELETE FROM grid_player_buffs
    WHERE steamid = p_steamid;
END$$

-- Global Settings Procedure
CREATE OR REPLACE PROCEDURE grid_set_setting(
    IN p_key VARCHAR(64),
    IN p_val TEXT
)
BEGIN
    INSERT INTO grid_settings (`key`, `val`)
    VALUES (p_key, p_val)
    ON DUPLICATE KEY UPDATE `val` = p_val;
END$$

-- --------------------------------------------------------
-- Auction House Stored Procedures
-- --------------------------------------------------------

CREATE OR REPLACE PROCEDURE grid_auction_create(
    IN p_seller_steamid VARCHAR(20),
    IN p_seller_name VARCHAR(64),
    IN p_inv_id BIGINT UNSIGNED,
    IN p_start_bid BIGINT UNSIGNED,
    IN p_buyout_price BIGINT UNSIGNED,
    IN p_duration_hours TINYINT UNSIGNED,
    IN p_deposit_amount BIGINT UNSIGNED,
    IN p_now_unix INT UNSIGNED,
    OUT p_out_status VARCHAR(32),
    OUT p_out_auction_id BIGINT UNSIGNED
)
BEGIN
    DECLARE v_active_count INT DEFAULT 0;
    DECLARE v_item_id VARCHAR(64);
    DECLARE v_item_type VARCHAR(32);
    DECLARE v_amount INT;
    DECLARE v_item_data JSON;
    DECLARE v_seller_money BIGINT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_out_status = 'ERROR_SQL';
        SET p_out_auction_id = 0;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_active_count
    FROM grid_auctions
    WHERE seller_steamid = p_seller_steamid AND status = 'ACTIVE';

    IF v_active_count >= 10 THEN
        SET p_out_status = 'ERR_MAX_LISTINGS';
        SET p_out_auction_id = 0;
        ROLLBACK;
    ELSE
        SELECT money INTO v_seller_money
        FROM grid_players
        WHERE steamid = p_seller_steamid
        FOR UPDATE;

        IF v_seller_money < p_deposit_amount THEN
            SET p_out_status = 'ERR_INSUFFICIENT_FUNDS';
            SET p_out_auction_id = 0;
            ROLLBACK;
        ELSE
            SELECT item_id, item_type, amount, item_data
            INTO v_item_id, v_item_type, v_amount, v_item_data
            FROM grid_inventory
            WHERE id = p_inv_id AND steamid = p_seller_steamid
            FOR UPDATE;

            IF v_item_id IS NULL THEN
                SET p_out_status = 'ERR_ITEM_NOT_FOUND';
                SET p_out_auction_id = 0;
                ROLLBACK;
            ELSE
                DELETE FROM grid_inventory WHERE id = p_inv_id;

                UPDATE grid_players
                SET money = money - p_deposit_amount
                WHERE steamid = p_seller_steamid;

                INSERT INTO grid_auctions (
                    seller_steamid, seller_name, item_id, item_type, amount, item_data,
                    start_bid, current_bid, buyout_price, deposit_amount, status,
                    duration_hours, created_at_unix, expires_at_unix
                ) VALUES (
                    p_seller_steamid, p_seller_name, v_item_id, v_item_type, v_amount, v_item_data,
                    p_start_bid, 0, p_buyout_price, p_deposit_amount, 'ACTIVE',
                    p_duration_hours, p_now_unix, p_now_unix + (p_duration_hours * 3600)
                );

                SET p_out_auction_id = LAST_INSERT_ID();
                SET p_out_status = 'SUCCESS';

                INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
                VALUES (p_now_unix, 'ECONOMY', 'AUCTION_LIST', p_seller_steamid, p_deposit_amount, JSON_OBJECT('item_id', v_item_id, 'auction_id', p_out_auction_id, 'buyout', p_buyout_price, 'start_bid', p_start_bid));

                COMMIT;
            END IF;
        END IF;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_auction_bid(
    IN p_auction_id BIGINT UNSIGNED,
    IN p_bidder_steamid VARCHAR(20),
    IN p_bidder_name VARCHAR(64),
    IN p_bid_amount BIGINT UNSIGNED,
    IN p_now_unix INT UNSIGNED,
    OUT p_out_status VARCHAR(32)
)
BEGIN
    DECLARE v_seller_steamid VARCHAR(20);
    DECLARE v_status VARCHAR(16);
    DECLARE v_expires_at_unix INT UNSIGNED;
    DECLARE v_start_bid BIGINT UNSIGNED;
    DECLARE v_current_bid BIGINT UNSIGNED;
    DECLARE v_buyout_price BIGINT UNSIGNED;
    DECLARE v_prev_bidder VARCHAR(20);
    DECLARE v_bidder_money BIGINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_out_status = 'ERROR_SQL';
    END;

    START TRANSACTION;

    SELECT seller_steamid, status, expires_at_unix, start_bid, current_bid, buyout_price, high_bidder_steamid
    INTO v_seller_steamid, v_status, v_expires_at_unix, v_start_bid, v_current_bid, v_buyout_price, v_prev_bidder
    FROM grid_auctions
    WHERE auction_id = p_auction_id
    FOR UPDATE;

    IF v_status IS NULL OR v_status != 'ACTIVE' THEN
        SET p_out_status = 'ERR_NOT_ACTIVE';
        ROLLBACK;
    ELSEIF v_expires_at_unix <= p_now_unix THEN
        SET p_out_status = 'ERR_EXPIRED';
        ROLLBACK;
    ELSEIF v_seller_steamid = p_bidder_steamid THEN
        SET p_out_status = 'ERR_SELF_BID';
        ROLLBACK;
    ELSEIF (v_current_bid = 0 AND p_bid_amount < v_start_bid) OR (v_current_bid > 0 AND p_bid_amount <= v_current_bid) THEN
        SET p_out_status = 'ERR_BID_TOO_LOW';
        ROLLBACK;
    ELSE
        SELECT money INTO v_bidder_money
        FROM grid_players
        WHERE steamid = p_bidder_steamid
        FOR UPDATE;

        IF v_bidder_money < p_bid_amount THEN
            SET p_out_status = 'ERR_INSUFFICIENT_FUNDS';
            ROLLBACK;
        ELSE
            IF v_prev_bidder IS NOT NULL AND v_prev_bidder != '' AND v_current_bid > 0 THEN
                UPDATE grid_players
                SET money = money + v_current_bid
                WHERE steamid = v_prev_bidder;
            END IF;

            UPDATE grid_players
            SET money = money - p_bid_amount
            WHERE steamid = p_bidder_steamid;

            UPDATE grid_auctions
            SET current_bid = p_bid_amount,
                high_bidder_steamid = p_bidder_steamid,
                high_bidder_name = p_bidder_name
            WHERE auction_id = p_auction_id;

            SET p_out_status = 'SUCCESS';

            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (p_now_unix, 'ECONOMY', 'AUCTION_BID', p_bidder_steamid, v_seller_steamid, p_bid_amount, JSON_OBJECT('auction_id', p_auction_id));

            COMMIT;
        END IF;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_auction_buyout(
    IN p_auction_id BIGINT UNSIGNED,
    IN p_buyer_steamid VARCHAR(20),
    IN p_buyer_name VARCHAR(64),
    IN p_now_unix INT UNSIGNED,
    OUT p_out_status VARCHAR(32)
)
BEGIN
    DECLARE v_seller_steamid VARCHAR(20);
    DECLARE v_status VARCHAR(16);
    DECLARE v_expires_at_unix INT UNSIGNED;
    DECLARE v_buyout_price BIGINT UNSIGNED;
    DECLARE v_current_bid BIGINT UNSIGNED;
    DECLARE v_prev_bidder VARCHAR(20);
    DECLARE v_deposit_amount BIGINT UNSIGNED;
    DECLARE v_item_id VARCHAR(64);
    DECLARE v_item_type VARCHAR(32);
    DECLARE v_amount INT;
    DECLARE v_item_data JSON;
    DECLARE v_buyer_money BIGINT;
    DECLARE v_tax BIGINT UNSIGNED;
    DECLARE v_seller_payout BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_out_status = 'ERROR_SQL';
    END;

    START TRANSACTION;

    SELECT seller_steamid, status, expires_at_unix, buyout_price, current_bid, high_bidder_steamid,
           deposit_amount, item_id, item_type, amount, item_data
    INTO v_seller_steamid, v_status, v_expires_at_unix, v_buyout_price, v_current_bid, v_prev_bidder,
         v_deposit_amount, v_item_id, v_item_type, v_amount, v_item_data
    FROM grid_auctions
    WHERE auction_id = p_auction_id
    FOR UPDATE;

    IF v_status IS NULL OR v_status != 'ACTIVE' THEN
        SET p_out_status = 'ERR_NOT_ACTIVE';
        ROLLBACK;
    ELSEIF v_expires_at_unix <= p_now_unix THEN
        SET p_out_status = 'ERR_EXPIRED';
        ROLLBACK;
    ELSEIF v_buyout_price = 0 THEN
        SET p_out_status = 'ERR_NO_BUYOUT';
        ROLLBACK;
    ELSEIF v_seller_steamid = p_buyer_steamid THEN
        SET p_out_status = 'ERR_SELF_BUY';
        ROLLBACK;
    ELSE
        SELECT money INTO v_buyer_money
        FROM grid_players
        WHERE steamid = p_buyer_steamid
        FOR UPDATE;

        IF v_buyer_money < v_buyout_price THEN
            SET p_out_status = 'ERR_INSUFFICIENT_FUNDS';
            ROLLBACK;
        ELSE
            IF v_prev_bidder IS NOT NULL AND v_prev_bidder != '' AND v_current_bid > 0 THEN
                UPDATE grid_players
                SET money = money + v_current_bid
                WHERE steamid = v_prev_bidder;
            END IF;

            UPDATE grid_players
            SET money = money - v_buyout_price
            WHERE steamid = p_buyer_steamid;

            SET v_tax = FLOOR(v_buyout_price * 0.075);
            SET v_seller_payout = (v_buyout_price - v_tax) + v_deposit_amount;

            UPDATE grid_players
            SET money = money + v_seller_payout
            WHERE steamid = v_seller_steamid;

            INSERT INTO grid_auction_collection (
                steamid, item_id, item_type, amount, item_data,
                source_reason, source_auction_id, created_at_unix, claimed
            ) VALUES (
                p_buyer_steamid, v_item_id, v_item_type, v_amount, v_item_data,
                'WON_AUCTION', p_auction_id, p_now_unix, 0
            );

            UPDATE grid_auctions
            SET status = 'SOLD',
                closed_at_unix = p_now_unix,
                high_bidder_steamid = p_buyer_steamid,
                high_bidder_name = p_buyer_name,
                current_bid = v_buyout_price
            WHERE auction_id = p_auction_id;

            SET p_out_status = 'SUCCESS';

            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (p_now_unix, 'ECONOMY', 'AUCTION_SALE', p_buyer_steamid, v_seller_steamid, v_tax, JSON_OBJECT('auction_id', p_auction_id, 'item_id', v_item_id, 'buyout', v_buyout_price, 'tax', v_tax, 'payout', v_seller_payout));

            COMMIT;
        END IF;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_auction_cancel(
    IN p_auction_id BIGINT UNSIGNED,
    IN p_seller_steamid VARCHAR(20),
    IN p_now_unix INT UNSIGNED,
    OUT p_out_status VARCHAR(32)
)
BEGIN
    DECLARE v_status VARCHAR(16);
    DECLARE v_seller_steamid VARCHAR(20);
    DECLARE v_current_bid BIGINT UNSIGNED;
    DECLARE v_item_id VARCHAR(64);
    DECLARE v_item_type VARCHAR(32);
    DECLARE v_amount INT;
    DECLARE v_item_data JSON;
    DECLARE v_deposit_amount BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_out_status = 'ERROR_SQL';
    END;

    START TRANSACTION;

    SELECT status, seller_steamid, current_bid, item_id, item_type, amount, item_data, deposit_amount
    INTO v_status, v_seller_steamid, v_current_bid, v_item_id, v_item_type, v_amount, v_item_data, v_deposit_amount
    FROM grid_auctions
    WHERE auction_id = p_auction_id
    FOR UPDATE;

    IF v_status IS NULL OR v_status != 'ACTIVE' THEN
        SET p_out_status = 'ERR_NOT_ACTIVE';
        ROLLBACK;
    ELSEIF v_seller_steamid != p_seller_steamid THEN
        SET p_out_status = 'ERR_NOT_OWNER';
        ROLLBACK;
    ELSEIF v_current_bid > 0 THEN
        SET p_out_status = 'ERR_HAS_BIDS';
        ROLLBACK;
    ELSE
        INSERT INTO grid_auction_collection (
            steamid, item_id, item_type, amount, item_data,
            source_reason, source_auction_id, created_at_unix, claimed
        ) VALUES (
            p_seller_steamid, v_item_id, v_item_type, v_amount, v_item_data,
            'CANCELLED_AUCTION', p_auction_id, p_now_unix, 0
        );

        UPDATE grid_auctions
        SET status = 'CANCELLED',
            closed_at_unix = p_now_unix
        WHERE auction_id = p_auction_id;

        SET p_out_status = 'SUCCESS';

        INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
        VALUES (p_now_unix, 'ECONOMY', 'AUCTION_CANCEL', p_seller_steamid, v_deposit_amount, JSON_OBJECT('auction_id', p_auction_id, 'deposit_forfeited', v_deposit_amount));

        COMMIT;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_auction_claim_collection(
    IN p_collection_id BIGINT UNSIGNED,
    IN p_steamid VARCHAR(20),
    IN p_bag_index TINYINT UNSIGNED,
    IN p_slot_index TINYINT UNSIGNED,
    IN p_now_unix INT UNSIGNED,
    OUT p_out_status VARCHAR(32)
)
BEGIN
    DECLARE v_item_id VARCHAR(64);
    DECLARE v_item_type VARCHAR(32);
    DECLARE v_amount INT;
    DECLARE v_item_data JSON;
    DECLARE v_claimed TINYINT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_out_status = 'ERROR_SQL';
    END;

    START TRANSACTION;

    SELECT item_id, item_type, amount, item_data, claimed
    INTO v_item_id, v_item_type, v_amount, v_item_data, v_claimed
    FROM grid_auction_collection
    WHERE collection_id = p_collection_id AND steamid = p_steamid
    FOR UPDATE;

    IF v_item_id IS NULL THEN
        SET p_out_status = 'ERR_NOT_FOUND';
        ROLLBACK;
    ELSEIF v_claimed = 1 THEN
        SET p_out_status = 'ERR_ALREADY_CLAIMED';
        ROLLBACK;
    ELSE
        INSERT INTO grid_inventory (steamid, bag_index, slot_index, item_id, item_type, amount, item_data)
        VALUES (p_steamid, p_bag_index, p_slot_index, v_item_id, v_item_type, v_amount, v_item_data);

        UPDATE grid_auction_collection
        SET claimed = 1,
            claimed_at_unix = p_now_unix
        WHERE collection_id = p_collection_id;

        SET p_out_status = 'SUCCESS';
        COMMIT;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_auction_process_expirations(
    IN p_now_unix INT UNSIGNED
)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_auc_id BIGINT UNSIGNED;
    DECLARE v_seller VARCHAR(20);
    DECLARE v_bidder VARCHAR(20);
    DECLARE v_bidder_name VARCHAR(64);
    DECLARE v_cur_bid BIGINT UNSIGNED;
    DECLARE v_deposit BIGINT UNSIGNED;
    DECLARE v_item_id VARCHAR(64);
    DECLARE v_item_type VARCHAR(32);
    DECLARE v_amount INT;
    DECLARE v_item_data JSON;
    DECLARE v_tax BIGINT UNSIGNED;
    DECLARE v_payout BIGINT UNSIGNED;

    DECLARE cur CURSOR FOR 
        SELECT auction_id, seller_steamid, high_bidder_steamid, high_bidder_name, current_bid,
               deposit_amount, item_id, item_type, amount, item_data
        FROM grid_auctions
        WHERE status = 'ACTIVE' AND expires_at_unix <= p_now_unix;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO v_auc_id, v_seller, v_bidder, v_bidder_name, v_cur_bid,
                       v_deposit, v_item_id, v_item_type, v_amount, v_item_data;
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF v_cur_bid > 0 AND v_bidder IS NOT NULL AND v_bidder != '' THEN
            SET v_tax = FLOOR(v_cur_bid * 0.075);
            SET v_payout = (v_cur_bid - v_tax) + v_deposit;

            UPDATE grid_players SET money = money + v_payout WHERE steamid = v_seller;

            INSERT INTO grid_auction_collection (
                steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
            ) VALUES (
                v_bidder, v_item_id, v_item_type, v_amount, v_item_data, 'WON_AUCTION', v_auc_id, p_now_unix, 0
            );

            UPDATE grid_auctions
            SET status = 'SOLD', closed_at_unix = p_now_unix
            WHERE auction_id = v_auc_id;

            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, target_steamid, numeric_value, metadata)
            VALUES (p_now_unix, 'ECONOMY', 'AUCTION_EXPIRE_SOLD', v_bidder, v_seller, v_tax, JSON_OBJECT('auction_id', v_auc_id, 'tax', v_tax, 'payout', v_payout));
        ELSE
            INSERT INTO grid_auction_collection (
                steamid, item_id, item_type, amount, item_data, source_reason, source_auction_id, created_at_unix, claimed
            ) VALUES (
                v_seller, v_item_id, v_item_type, v_amount, v_item_data, 'EXPIRED_AUCTION', v_auc_id, p_now_unix, 0
            );

            UPDATE grid_auctions
            SET status = 'EXPIRED', closed_at_unix = p_now_unix
            WHERE auction_id = v_auc_id;

            INSERT INTO grid_telemetry (unix_ts, category, action_type, actor_steamid, numeric_value, metadata)
            VALUES (p_now_unix, 'ECONOMY', 'AUCTION_EXPIRE_UNSOLD', v_seller, v_deposit, JSON_OBJECT('auction_id', v_auc_id, 'deposit_forfeited', v_deposit));
        END IF;
    END LOOP;

    CLOSE cur;
END$$

-- Persistent Map Entities Procedures
CREATE OR REPLACE PROCEDURE grid_save_map_entity(
    IN p_spawn_id INT UNSIGNED,
    IN p_map VARCHAR(64),
    IN p_class VARCHAR(64),
    IN p_x FLOAT, IN p_y FLOAT, IN p_z FLOAT,
    IN p_p FLOAT, IN p_yaw FLOAT, IN p_r FLOAT,
    IN p_admin_sid VARCHAR(20),
    IN p_custom_data JSON
)
BEGIN
    IF p_spawn_id > 0 THEN
        UPDATE grid_map_entities
        SET pos_x = p_x, pos_y = p_y, pos_z = p_z,
            ang_p = p_p, ang_y = p_yaw, ang_r = p_r,
            custom_data = COALESCE(p_custom_data, custom_data)
        WHERE spawn_id = p_spawn_id;
        SELECT p_spawn_id AS spawn_id;
    ELSE
        INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data)
        VALUES (p_map, p_class, p_x, p_y, p_z, p_p, p_yaw, p_r, p_admin_sid, p_custom_data);
        SELECT LAST_INSERT_ID() AS spawn_id;
    END IF;
END$$

CREATE OR REPLACE PROCEDURE grid_delete_map_entity(IN p_spawn_id INT UNSIGNED)
BEGIN
    DELETE FROM grid_map_entities WHERE spawn_id = p_spawn_id;
END$$

CREATE OR REPLACE PROCEDURE grid_copy_map_spawns(IN p_old_map VARCHAR(64), IN p_new_map VARCHAR(64))
BEGIN
    INSERT INTO grid_map_entities (map_name, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data)
    SELECT p_new_map, class_name, pos_x, pos_y, pos_z, ang_p, ang_y, ang_r, placed_by, custom_data
    FROM grid_map_entities WHERE map_name = p_old_map;
END$$

DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;

