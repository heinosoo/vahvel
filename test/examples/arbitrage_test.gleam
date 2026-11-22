//// Currency arbitrage: a loop of exchanges that ends with more money than it
//// started with. Trades are keyed by currency pair, euros and pounds must
//// balance, and the objective is the dollars gained. With fair rates the best
//// trade is none; with one rate slightly off, the gain is unbounded.

import gleam/float
import gleam/list
import gleam/result
import vahvel.{Constant, Difference, Linear, Sum, Variable}

type Currency {
  Usd
  Eur
  Gbp
}

// How much of `from` to sell for `to`.
type Trade {
  Trade(from: Currency, to: Currency)
}

// One unit of `from` buys `rate` units of `to`.
type Rate {
  Rate(from: Currency, to: Currency, rate: Float)
}

// Every rate but pounds to dollars is fixed. At 1.25 every loop loses the
// spread.
fn rates(gbp_to_usd: Float) -> List(Rate) {
  [
    Rate(Usd, Eur, 0.875),
    Rate(Eur, Usd, 1.125),
    Rate(Eur, Gbp, 0.875),
    Rate(Gbp, Eur, 1.125),
    Rate(Usd, Gbp, 0.75),
    Rate(Gbp, Usd, gbp_to_usd),
  ]
}

fn sold(rates: List(Rate), currency: Currency) -> vahvel.Expression(Trade) {
  list.filter(rates, fn(rate) { rate.from == currency })
  |> list.map(fn(rate) { Variable(Trade(rate.from, rate.to)) })
  |> Sum
}

fn received(rates: List(Rate), currency: Currency) -> vahvel.Expression(Trade) {
  list.filter(rates, fn(rate) { rate.to == currency })
  |> list.map(fn(rate) { Linear(rate.rate, Trade(rate.from, rate.to)) })
  |> Sum
}

fn arbitrage(rates: List(Rate)) -> vahvel.Model(Trade) {
  let net = fn(currency) {
    Difference(received(rates, currency), sold(rates, currency))
  }
  vahvel.Model(
    domain: fn(_) { vahvel.NonNegativeReal },
    objective: vahvel.Maximize(net(Usd)),
    // Euros and pounds only pass through: every one bought is sold again.
    constraints: [
      vahvel.Equal(net(Eur), Constant(0.0)),
      vahvel.Equal(net(Gbp), Constant(0.0)),
    ],
  )
}

// The simplex method works within a tolerance, so a continuous answer can be
// off in its last digits even when the exact answer is a whole number.
fn rounded(value: Result(Float, Nil)) -> Result(Int, Nil) {
  result.map(value, float.round)
}

pub fn fair_rates_test() {
  let assert Ok(vahvel.Optimal(solution, _)) =
    vahvel.solve(arbitrage(rates(1.25)))
  assert float.round(vahvel.objective(solution)) == 0
}

pub fn free_money_test() {
  // At 1.3125, dollars → pounds → dollars still loses, but dollars → euros →
  // pounds → dollars gains half a percent. Repeating the loop gains without
  // limit, so `Unbounded` is the answer, not a modeling mistake.
  assert vahvel.solve(arbitrage(rates(1.3125))) == Ok(vahvel.Unbounded)
}

pub fn daily_limit_test() {
  // A bank that sells at most 1024 dollars a day caps the gain, and the
  // trades show the loop: 1024 dollars → 896 euros → 784 pounds → 1029
  // dollars.
  let rates = rates(1.3125)
  let model = arbitrage(rates)
  let limit = vahvel.LessEqual(sold(rates, Usd), Constant(1024.0))
  let assert Ok(vahvel.Optimal(solution, _)) =
    vahvel.solve(
      vahvel.Model(..model, constraints: [limit, ..model.constraints]),
    )
  assert float.round(vahvel.objective(solution)) == 5
  assert rounded(vahvel.value(solution, Trade(Usd, Eur))) == Ok(1024)
  assert rounded(vahvel.value(solution, Trade(Eur, Gbp))) == Ok(896)
  assert rounded(vahvel.value(solution, Trade(Gbp, Usd))) == Ok(784)
}
