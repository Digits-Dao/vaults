// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title PendingDeposit
 * @author Teragon
 *
 * Adopted from https://github.com/edag94/solidity-queue
 */

library PendingDeposit {
    struct Item {
        uint256 blockNumber;
        address depositor;
        uint256 amount;
    }

    struct Queue {
        mapping(uint256 => Item) _pendingDeposits;
        uint256 _first;
        uint256 _last;
    }

    modifier isNotEmpty(Queue storage queue) {
        require(!isEmpty(queue), "Queue is empty.");
        _;
    }

    /**
     * @dev Gets the number of elements in the queue. O(1)
     * @param queue Queue struct from contract.
     */
    function length(Queue storage queue) internal view returns (uint256) {
        if (queue._last <= queue._first) {
            return 0;
        }
        return queue._last - queue._first;
    }

    /**
     * @dev Returns if queue is empty. O(1)
     * @param queue Queue struct from contract.
     */
    function isEmpty(Queue storage queue) internal view returns (bool) {
        return length(queue) == 0;
    }

    /**
     * @dev Adds an element to the back of the queue. O(1)
     * @param queue Queue struct from contract.
     * @param pendingDeposit The added element's pendingDeposit.
     */
    function enqueue(Queue storage queue, Item memory pendingDeposit) internal {
        queue._pendingDeposits[queue._last++] = pendingDeposit;
    }

    /**
     * @dev Removes an element from the front of the queue and returns it. O(1)
     * @param queue Queue struct from contract.
     */
    function dequeue(Queue storage queue)
        internal
        isNotEmpty(queue)
        returns (Item memory pendingDeposit)
    {
        pendingDeposit = queue._pendingDeposits[queue._first];
        delete queue._pendingDeposits[queue._first++];
    }

    /**
     * @dev Returns the pendingDeposit from the front of the queue, without removing it. O(1)
     * @param queue Queue struct from contract.
     */
    function peek(Queue storage queue)
        internal
        view
        isNotEmpty(queue)
        returns (Item memory pendingDeposit)
    {
        return queue._pendingDeposits[queue._first];
    }

    /**
     * @dev Returns the pendingDeposit from the back of the queue. O(1)
     * @param queue Queue struct from contract.
     */
    function peekLast(Queue storage queue)
        internal
        view
        isNotEmpty(queue)
        returns (Item memory pendingDeposit)
    {
        return queue._pendingDeposits[queue._last - 1];
    }

    function peekIndex(Queue storage queue, uint256 index)
        internal
        view
        isNotEmpty(queue)
        returns (Item memory pendingDeposit)
    {
        require(queue._first + index < queue._last, "Index out of bound");
        return queue._pendingDeposits[queue._first + index];
    }
}
