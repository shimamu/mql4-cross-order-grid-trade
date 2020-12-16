//+------------------------------------------------------------------+
//|                                          CrossOrderGridTrade.mq4 |
//|                                         Copyright 2020, shimamu. |
//|                                       https://github.com/shimamu |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, shimamu."
#property link      "https://github.com/shimamu"
#property version   "1.02"
#property strict

#include <stdlib.mqh>

// Parameter.
extern double UnitLots = 0.04; // UnitLots(1 Lot = 100,000 currency.)
extern double GridSpace = 0.25;
extern double BuyMaxRate = 109.95;
extern double BuyMinRate = 100.2;
extern double SellMaxRate = 114.95;
extern double SellMinRate = 104.2;

// Constant variables.
int SECOND_DECIMAL_PIONT = 2;

// Global variables.
int MagicNumber = 20201116;
int Slippage = 3;
int MiliSecondsAfterRequest = 1000;
int MiliSecondsAfterError = 1000;

//+------------------------------------------------------------------+
class Order {
private:
    double _lots;
    double _rate;
    int _slippage;
    color _arrowColor;

public:
    Order(double lots, double rate, int slippage, color arrow_color) {
        _lots = lots;
        _rate = rate;
        _slippage = slippage;
        _arrowColor = arrow_color;
    }

    double lots() {
        return _lots;
    }

    double rate() {
        return _rate;
    }

    int slippage() {
        return _slippage;
    }

    color arrowColor() {
        return _arrowColor;
    }
};

//+------------------------------------------------------------------+
class EntryOrder : public Order {
private:
    int _orderType;
    int _magicNumber;

public:
    EntryOrder(int order_type, double lots, double rate, int slippage, int magic_number, color arrow_color)
        : Order(lots, rate, slippage, arrow_color) {
        _orderType = order_type;
        _magicNumber = magic_number;
    }

    string currencyPair() {
        return Symbol();
    }

    int orderType() {
        return _orderType;
    }

    int magicNumber() {
        return _magicNumber;
    }
};

//+------------------------------------------------------------------+
class ExitOrder : public Order {
private:
    int _ticket;

public:
    ExitOrder(int ticket, double lots, double rate, int slippage, color arrow_color)
        : Order(lots, rate, slippage, arrow_color) {
        _ticket = ticket;
    }

    int ticket() {
        return _ticket;
    }
};

//+------------------------------------------------------------------+
class Range {
private:
    double _maxRate;
    double _minRate;

public:
    Range(double max_rate, double min_rate) {
        _maxRate = max_rate;
        _minRate = min_rate;
    }

    double maxRate() {
        return _maxRate;
    }

    double minRate() {
        return _minRate;
    }
};

//+------------------------------------------------------------------+
class EntryLimit : public Range {
public:
    EntryLimit(double max_rate, double min_rate)
        : Range(max_rate, min_rate) {
    }
};

//+------------------------------------------------------------------+
class Target {
private:
    double _lastOrderRate;
    double _profit;

public:
    Target(double target_entry_rate, double profit) {
        _lastOrderRate = target_entry_rate + profit;
        _profit = profit;
    }

    double entryRate() {
        return _lastOrderRate - _profit;
    }

    double exitRate() {
        return _lastOrderRate + _profit;
    }

    double lastOrderRate() {
        return _lastOrderRate;
    }

    void moveHigh() {
        _lastOrderRate += _profit;
    }

    void moveLow() {
        _lastOrderRate -= _profit;
    }

    Range* rangeOfTheSideOfEntry() {
        double max_rate = lastOrderRate();
        double min_rate = entryRate();
        return (min_rate < max_rate) ? new Range(max_rate, min_rate) : new Range(min_rate, max_rate);
    }
};

//+------------------------------------------------------------------+
class Securities {
private:
    void checkError(string msg) {
        int error_code = GetLastError();
        if (error_code != ERR_NO_ERROR) {
            printf(
                "Error in (%s)  code:%d,  detail:%s ",
                msg,
                error_code,
                ErrorDescription(error_code));
        }
    }

public:
    int entry(EntryOrder* entry_order) {
        if (entry_order == NULL) {
            return 0;
        }
        int ticket = OrderSend(
                         entry_order.currencyPair(),
                         entry_order.orderType(),
                         entry_order.lots(),
                         entry_order.rate(),
                         entry_order.slippage(),
                         0,
                         0,
                         NULL,
                         entry_order.magicNumber(),
                         0,
                         entry_order.arrowColor());
        if (ticket > 0) {
            Sleep(MiliSecondsAfterRequest);
        } else {
            checkError("OrderSend");
            Sleep(MiliSecondsAfterError);
        }
        return ticket;
    }

    bool exit(ExitOrder* exit_order) {
        if (exit_order == NULL) {
            return false;
        }
        bool success = OrderClose(
                           exit_order.ticket(),
                           exit_order.lots(),
                           exit_order.rate(),
                           exit_order.slippage(),
                           exit_order.arrowColor());
        if (success) {
            Sleep(MiliSecondsAfterRequest);
        } else {
            checkError("OrderClose");
            Sleep(MiliSecondsAfterError);
        }
        return success;
    }
};

//+------------------------------------------------------------------+
class Position {
private:
    int _orderType;
    int _magicNumber;

public:
    Position(int order_type, int magic_number) {
        _orderType = order_type;
        _magicNumber = magic_number;
    }

    bool isNone() {
        return (totalLots() <= 0);
    }

    int lastOrderTicket() {
        int ticket = 0;
        for (int i = 0; i < OrdersTotal(); i++) {
            bool success = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
            if (!success) {
                return 0;
            }

            // Check currency pair.
            if (OrderSymbol() != Symbol()) {
                continue;
            }

            if (OrderMagicNumber() != _magicNumber) {
                continue;
            }

            if (OrderType() == _orderType) {
                ticket = OrderTicket();
            }
        }

        return ticket;
    }

    double totalLots() {
        double lots = 0;
        for (int i = 0; i < OrdersTotal(); i++) {
            bool success = OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
            if (!success) {
                return 0;
            }

            // Check currency pair.
            if (OrderSymbol() != Symbol()) {
                continue;
            }

            if (OrderMagicNumber() != _magicNumber) {
                continue;
            }

            if (OrderType() == _orderType) {
                lots += OrderLots();
            }
        }

        return NormalizeDouble(lots, SECOND_DECIMAL_PIONT);
    }
};

//+------------------------------------------------------------------+
class EntryUnit {
private:
    double _gridSpace;
    double _lots;

public:
    EntryUnit(double lots, double grid_space) {
        _gridSpace = grid_space;
        _lots = lots;
    }

    int countGridsBetween(double rate_a, double rate_b) {
        return int(MathAbs(rate_a - rate_b) / _gridSpace) + 1;
    }

    double gridSpace() {
        return _gridSpace;
    }

    double lots() {
        return _lots;
    }
};

//+------------------------------------------------------------------+
class Current {
private:
    double _entryRate;
    double _exitRate;

public:
    Current(double entry_rate, double exit_rate) {
        _entryRate = entry_rate;
        _exitRate = exit_rate;
    }

    double entryRate() {
        return _entryRate;
    }

    double exitRate() {
        return _exitRate;
    }

    bool isEntryRateIn(Range* range) {
        return (range.minRate() <= _entryRate) && (_entryRate <= range.maxRate());
    }
};

//+------------------------------------------------------------------+
//| Common order rule.                                               |
//+------------------------------------------------------------------+
class OrderRule {
protected:
    int _orderType;
    string _orderTypeLabel;
    EntryLimit* _entryLimit;
    EntryUnit* _entryUnit;
    color _entryColor;
    color _exitColor;
    Position* _position;
    Target* _target;
    virtual Current* current() = 0;
    virtual bool isEntrySign() = 0;
    virtual bool isExitSign() = 0;
    virtual double highestRiskEntryRate() = 0;

    double countEntryLots() {
        if (!current().isEntryRateIn(_entryLimit)) {
            return 0;
        }
        int need_grids = _entryUnit.countGridsBetween(current().entryRate(), highestRiskEntryRate());
        double need_lots = need_grids * _entryUnit.lots();
        double entry_lots = need_lots - _position.totalLots();
        return NormalizeDouble(entry_lots, SECOND_DECIMAL_PIONT);
    }

    bool hasLotsForEntryTarget() {
        return (countEntryLots() < 0);
    }

    bool hasTargetEntryLots() {
        return (current().isEntryRateIn(_target.rangeOfTheSideOfEntry())
                && hasLotsForEntryTarget());
    }

    void printTarget() {
        printf(
            "-> next %s  entry:%.3f  exit:%.3f",
            _orderTypeLabel,
            _target.entryRate(),
            _target.exitRate());
    }

public:
    OrderRule(EntryLimit* entry_limit, EntryUnit* entry_unit) {
        _entryLimit = entry_limit;
        _entryUnit = entry_unit;
    }

    EntryOrder* createEntryOrder() {
        if (hasTargetEntryLots()) {
            updateAfterEntry();
            return NULL;
        }

        if (!isEntrySign()) {
            return NULL;
        }

        double entry_lots = countEntryLots();
        if (entry_lots <= 0) {
            updateAfterEntry();
            return NULL;
        }
        EntryOrder* order = new EntryOrder(_orderType,
                                           entry_lots,
                                           current().entryRate(),
                                           Slippage,
                                           MagicNumber,
                                           _entryColor);
        return order;
    }

    ExitOrder* createExitOrder() {
        if (_position.isNone()) {
            return NULL;
        }

        if (!isExitSign()) {
            return NULL;
        }

        ExitOrder* order = new ExitOrder(
            _position.lastOrderTicket(),
            _entryUnit.lots(),
            current().exitRate(),
            Slippage,
            _exitColor);
        return order;
    }

    void updateAfterExit() {
        _target.moveHigh();
        printTarget();
    }

    void updateAfterEntry() {
        _target.moveLow();
        printTarget();
    }
};

//+------------------------------------------------------------------+
//| Specifics of buy position.                                       |
//+------------------------------------------------------------------+
class BuyOrderRule: public OrderRule {
protected:
    virtual Current* current() {
        return new Current(Ask, Bid);
    }

    virtual bool isEntrySign() {
        return current().isEntryRateIn(_entryLimit)
               && (current().entryRate() <= _target.entryRate());
    }

    virtual bool isExitSign() {
        return (_target.exitRate() <= current().exitRate());
    }

    virtual double highestRiskEntryRate() {
        return _entryLimit.maxRate();
    }

public:
    void BuyOrderRule(EntryLimit* entry_limit, EntryUnit* entry_unit)
        : OrderRule(entry_limit, entry_unit) {
        _orderType = OP_BUY;
        _orderTypeLabel = "buy";
        _entryColor = clrAqua;
        _exitColor = clrBlue;
        _position = new Position(_orderType, MagicNumber);
        _target = new Target(_entryLimit.maxRate(), _entryUnit.gridSpace());
        printTarget();
    }
};

//+------------------------------------------------------------------+
//| Specifics of sell position.                                      |
//+------------------------------------------------------------------+
class SellOrderRule: public OrderRule {
protected:
    virtual Current* current() {
        return new Current(Bid, Ask);
    }

    virtual bool isEntrySign() {
        return current().isEntryRateIn(_entryLimit)
               && (_target.entryRate() <= current().entryRate());
    }

    virtual bool isExitSign() {
        return (current().exitRate() <= _target.exitRate());
    }

    virtual double highestRiskEntryRate() {
        return _entryLimit.minRate();
    }

public:
    void SellOrderRule(EntryLimit* entry_limit, EntryUnit* entry_unit)
        : OrderRule(entry_limit, entry_unit) {
        _orderType = OP_SELL;
        _orderTypeLabel = "sell";
        _entryColor = clrHotPink;
        _exitColor = clrRed;
        _position = new Position(_orderType, MagicNumber);
        _target = new Target(_entryLimit.minRate(), -_entryUnit.gridSpace());
        printTarget();
    }
};

//+------------------------------------------------------------------+
class CrossOrderGridTrade {
private:
    OrderRule* _orderRule;
    Securities* _securities;

public:
    CrossOrderGridTrade(OrderRule* order_rule) {
        _orderRule = order_rule;
        _securities = new Securities();
    }

    void checkForEntry() {
        EntryOrder* order = _orderRule.createEntryOrder();
        int ticket = _securities.entry(order);
        if (ticket > 0) {
            _orderRule.updateAfterEntry();
        }
    }

    void checkForExit() {
        ExitOrder* order = _orderRule.createExitOrder();
        bool success = _securities.exit(order);
        if (success) {
            _orderRule.updateAfterExit();
        }
    }

    void run() {
        checkForEntry();
        checkForExit();
    }
};

CrossOrderGridTrade* buyTrade;
CrossOrderGridTrade* sellTrade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
//---
    buyTrade = new CrossOrderGridTrade(
        new BuyOrderRule(
            new EntryLimit(BuyMaxRate, BuyMinRate),
            new EntryUnit(UnitLots, GridSpace)));

    sellTrade = new CrossOrderGridTrade(
        new SellOrderRule(
            new EntryLimit(SellMaxRate, SellMinRate),
            new EntryUnit(UnitLots, GridSpace)));
//---
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    buyTrade.run();
    sellTrade.run();
}
//+------------------------------------------------------------------+
