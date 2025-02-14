\connect rollup;

CREATE OR REPLACE VIEW unqueued_rollup_tx
AS

SELECT block.block_number, r.*
FROM l1_rollup_tx r
  INNER JOIN l1_tx tx ON r.l1_tx_hash = tx.tx_hash
  INNER JOIN l1_block block ON block.block_number = tx.block_number
WHERE
  r.geth_submission_queue_index IS NULL
  AND block.processed = TRUE
ORDER BY
  block.block_number ASC,
  r.l1_tx_index ASC,
  r.l1_tx_log_index ASC
;


CREATE OR REPLACE VIEW next_queued_geth_submission
AS

SELECT r.*, b.block_timestamp, b.block_number
FROM l1_rollup_tx r
  INNER JOIN l1_tx t ON r.l1_tx_hash = t.tx_hash
  INNER JOIN l1_block b ON b.block_number = t.block_number
WHERE
  r.geth_submission_queue_index = (SELECT MIN(queue_index)
                                   FROM geth_submission_queue
                                   WHERE status = 'QUEUED')
ORDER BY r.index_within_submission ASC
;


CREATE OR REPLACE VIEW next_verification_batch
AS

SELECT l1.batch_number, l1.batch_index, l1.state_root as l1_root, l2.state_root as geth_root
FROM l1_rollup_state_root l1
  LEFT OUTER JOIN l2_tx_output l2
      ON l1.batch_number = l2.state_commitment_chain_batch_number
         AND l1.batch_index = l2.state_commitment_chain_batch_index
WHERE
  l1.batch_number = (SELECT MIN(batch_number)
                     FROM l1_rollup_state_root_batch
                     WHERE status = 'UNVERIFIED')
  AND (SELECT COUNT(*)
       FROM l1_rollup_state_root_batch
       WHERE status = 'FRAUDULENT' OR status = 'REMOVED'
      ) = 0   -- there is no next_verification_batch if we're in a fraud workflow.
  AND l2.state_root IS NOT NULL
ORDER BY l1.batch_index ASC
;


CREATE OR REPLACE VIEW batchable_l2_only_tx_states
AS

SELECT tx.*, row_number() over (ORDER BY tx.id ASC) -1 AS row_number
FROM l2_tx_output tx
  INNER JOIN canonical_chain_batch cc
    ON tx.canonical_chain_batch_number = cc.batch_number
WHERE
  tx.state_commitment_chain_batch_number IS NULL
  AND cc.status = 'FINALIZED'
ORDER BY tx.block_number ASC, tx.tx_index ASC
;

/** Rollback script:
  DROP VIEW batchable_l2_only_tx_states;
  DROP VIEW next_verification_batch;
  DROP VIEW next_queued_geth_submission;
  DROP VIEW unqueued_rollup_tx;
 */

