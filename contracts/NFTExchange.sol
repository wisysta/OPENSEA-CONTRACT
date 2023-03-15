// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import "./structures/Order.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IProxy.sol";
import "./interfaces/IProxyRegistry.sol";

struct Sig {
    bytes32 r;
    bytes32 s;
    uint8 v;
}

contract NFTExchange is Ownable, ReentrancyGuard {
    bytes32 private constant ORDER_TYPEHASH =
        0x7d2606b3242cc6e6d31de9a58f343eed0d0647bd06fe84c19441d47d44316877;

    address public feeAddress;
    mapping(bytes32 => bool) public canceledOrFinalized;
    IProxyRegistry proxyRegistry;

    event OrdersMatched(
        bytes32 buyHash,
        bytes32 sellHash,
        address indexed maker,
        address indexed taker,
        uint256 price
    );

    constructor(address feeAddress_, address proxyRegistry_) {
        feeAddress = feeAddress_;
        proxyRegistry = IProxyRegistry(proxyRegistry_);
    }

    function setFeeAddress(address feeAddress_) external onlyOwner {
        feeAddress = feeAddress_;
    }

    function calculateMatchPrice(
        Order memory buy,
        Order memory sell
    ) internal view returns (uint256) {
        uint256 buyPrice = getOrderPrice(buy);
        uint256 sellPrice = getOrderPrice(sell);

        require(buyPrice >= sellPrice);

        return buyPrice;
    }

    function getOrderPrice(Order memory order) internal view returns (uint256) {
        if (order.saleKind == SaleKind.FIXED_PRICE) {
            return order.basePrice;
        } else {
            if (order.basePrice > order.endPrice) {
                return
                    order.basePrice -
                    (((block.timestamp - order.listingTime) *
                        (order.basePrice - order.endPrice)) /
                        (order.expirationTime - order.listingTime));
            } else {
                if (order.saleSide == SaleSide.SELL) {
                    return order.basePrice;
                } else {
                    return order.endPrice;
                }
            }
        }
    }

    function atomicMatch(
        Order memory buy,
        Sig memory buySig,
        Order memory sell,
        Sig memory sellSig
    ) external nonReentrant {
        bytes32 buyHash = validateOrder(buy, buySig);
        bytes32 sellHash = validateOrder(sell, sellSig);

        require(
            !canceledOrFinalized[buyHash] && !canceledOrFinalized[sellHash],
            "finalized order"
        );

        require(ordersCanMatch(buy, sell), "not matched");

        // 타겟주소가 CA인지 확인
        uint size;
        address target = sell.target;
        assembly {
            size := extcodesize(target)
        }
        require(size > 0);

        if (buy.replacementPattern.length > 0) {
            guardedArrayReplace(
                buy.calldata_,
                sell.calldata_,
                buy.replacementPattern
            );
        }

        if (sell.replacementPattern.length > 0) {
            guardedArrayReplace(
                sell.calldata_,
                buy.calldata_,
                sell.replacementPattern
            );
        }

        require(keccak256(buy.calldata_) == keccak256(sell.calldata_));

        canceledOrFinalized[buyHash] = true;
        canceledOrFinalized[sellHash] = true;

        uint256 price = excuteFundsTransfer(buy, sell);
        IProxy proxy = IProxy(proxyRegistry.proxies(sell.maker));

        require(proxy.proxy(sell.target, sell.calldata_));

        if (buy.staticTarget != address(0)) {
            require(staticCall(buy.target, buy.calldata_, buy.staticExtra));
        }

        if (sell.staticTarget != address(0)) {
            require(staticCall(sell.target, sell.calldata_, sell.staticExtra));
        }

        emit OrdersMatched(
            buyHash,
            sellHash,
            msg.sender == sell.maker ? sell.maker : buy.maker,
            msg.sender == sell.maker ? buy.maker : sell.maker,
            price
        );
    }

    function getFeePrice(uint256 price) internal pure returns (uint256) {
        return price / 40;
    }

    function excuteFundsTransfer(
        Order memory buy,
        Order memory sell
    ) internal returns (uint256 price) {
        if (sell.paymentToken != address(0)) {
            require(msg.value == 0);
        }

        price = calculateMatchPrice(buy, sell);
        uint256 fee = getFeePrice(price);

        if (price <= 0) {
            return 0;
        }

        if (sell.paymentToken != address(0)) {
            // ERC-20 토큰의 경우
            IERC20(sell.paymentToken).transferFrom(
                buy.maker,
                sell.maker,
                price
            );
            IERC20(sell.paymentToken).transferFrom(buy.maker, feeAddress, fee);
        } else {
            // 이더리움인 경우
            require(msg.sender == buy.maker);

            (bool result, ) = sell.maker.call{value: price}("");
            require(result);
            (result, ) = feeAddress.call{value: fee}("");
            require(result);

            uint256 remain = msg.value - price - fee;
            if (remain > 0) {
                (result, ) = msg.sender.call{value: remain}("");
                require(result);
            }
        }
    }

    function ordersCanMatch(
        Order memory buy,
        Order memory sell
    ) internal view returns (bool) {
        //최고가 매칭에서는 셀러만 트랜잭션 넣을 수 있도록
        if (
            sell.saleKind == SaleKind.AUCTION && sell.basePrice <= sell.endPrice
        ) {
            require(msg.sender == sell.maker);
        }

        return
            (buy.taker == address(0) || buy.taker == sell.maker) &&
            (sell.taker == address(0) || sell.taker == buy.taker) &&
            (buy.saleSide == SaleSide.BUY && sell.saleSide == SaleSide.SELL) &&
            (buy.target == sell.target) &&
            (buy.paymentToken == sell.paymentToken) &&
            (buy.basePrice == sell.basePrice) &&
            (sell.saleKind == SaleKind.FIXED_PRICE ||
                sell.basePrice <= sell.endPrice ||
                buy.endPrice == sell.endPrice) &&
            canSettleOrder(buy) &&
            canSettleOrder(sell);
    }

    function canSettleOrder(Order memory order) internal view returns (bool) {
        return (order.listingTime <= block.timestamp &&
            (order.expirationTime == 0 ||
                order.expirationTime >= block.timestamp));
    }

    function validateOrder(
        Order memory order,
        Sig memory sig
    ) internal view returns (bytes32 orderHash) {
        if (msg.sender != order.maker) {
            orderHash = validateOrderSig(order, sig);
        }

        require(order.exchange == address(this));

        if (order.saleKind == SaleKind.AUCTION) {
            require(order.expirationTime < order.listingTime);
        }
    }

    function validateOrderSig(
        Order memory order,
        Sig memory sig
    ) internal pure returns (bytes32 orderHash) {
        orderHash = hashOrder(order);
        require(ecrecover(orderHash, sig.v, sig.r, sig.s) == order.maker);
    }

    function hashOrder(Order memory order) public pure returns (bytes32 hash) {
        return
            keccak256(
                abi.encodePacked(
                    abi.encode(
                        ORDER_TYPEHASH,
                        order.exchange,
                        order.maker,
                        order.taker,
                        order.saleSide,
                        order.saleKind,
                        order.target,
                        order.paymentToken,
                        keccak256(order.calldata_),
                        keccak256(order.replacementPattern),
                        order.staticTarget,
                        keccak256(order.staticExtra)
                    ),
                    abi.encode(
                        order.basePrice,
                        order.endPrice,
                        order.listingTime,
                        order.expirationTime,
                        order.salt
                    )
                )
            );
    }

    function guardedArrayReplace(
        bytes memory array,
        bytes memory desired,
        bytes memory mask
    ) internal pure {
        require(array.length == desired.length);
        require(array.length == mask.length);

        uint words = array.length / 0x20;
        uint index = words * 0x20;
        assert(index / 0x20 == words);
        uint i;

        for (i = 0; i < words; i++) {
            /* Conceptually: array[i] = (!mask[i] && array[i]) || (mask[i] && desired[i]), bitwise in word chunks. */
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        }

        /* Deal with the last section of the byte array. */
        if (words > 0) {
            /* This overlaps with bytes already set but is still more efficient than iterating through each of the remaining bytes individually. */
            i = words;
            assembly {
                let commonIndex := mul(0x20, add(1, i))
                let maskValue := mload(add(mask, commonIndex))
                mstore(
                    add(array, commonIndex),
                    or(
                        and(not(maskValue), mload(add(array, commonIndex))),
                        and(maskValue, mload(add(desired, commonIndex)))
                    )
                )
            }
        } else {
            /* If the byte array is shorter than a word, we must unfortunately do the whole thing bytewise.
               (bounds checks could still probably be optimized away in assembly, but this is a rare case) */
            for (i = index; i < array.length; i++) {
                array[i] =
                    ((mask[i] ^ 0xff) & array[i]) |
                    (mask[i] & desired[i]);
            }
        }
    }

    function staticCall(
        address target,
        bytes memory calldata_,
        bytes memory extraCalldata_
    ) internal view returns (bool result) {
        bytes memory combined = bytes.concat(extraCalldata_, calldata_);
        uint256 combinedSize = combined.length;

        assembly {
            result := staticcall(
                gas(),
                target,
                combined,
                combinedSize,
                mload(0x40),
                0
            )
        }
    }
}
