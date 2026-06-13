import Foundation

enum HelpReference {
    static let title = "Friendly Compiler Language"

    static let overview = [
        "Casette accepts raw Sage input, plus a small command-first language that rewrites common calculator forms to Sage.",
        "A friendly command starts with a known word followed by a space. Function calls such as factor(x) bypass the compiler and run as raw Sage.",
        "Tape references like #14 stay visible while editing and expand only when the row is evaluated.",
    ]

    static let sections: [HelpSection] = [
        HelpSection(
            title: "Expression Transforms",
            summary: "Rewrite common symbolic expressions while keeping Sage visible in the preview line.",
            examples: [
                HelpExample(command: "expand (x+1)^5", detail: "Expand an expression.", sage: "expand((x+1)^5)"),
                HelpExample(command: "factor x^4 - 1", detail: "Factor symbolically.", sage: "factor(x^4 - 1)"),
                HelpExample(command: "simplify sin(x)^2 + cos(x)^2", detail: "Full simplification.", sage: "(sin(x)^2 + cos(x)^2).simplify_full()"),
                HelpExample(command: "latex x^2/2", detail: "Render Sage LaTeX for an expression.", sage: "latex(x^2/2)"),
            ]
        ),
        HelpSection(
            title: "Solving",
            summary: "Equations use one equals sign in friendly input; Casette lowers it to Sage equality.",
            examples: [
                HelpExample(command: "solve x^2 + 5*x + 6 = 0", detail: "Infer the only free variable.", sage: "solve(x^2 + 5*x + 6 == 0, x)"),
                HelpExample(command: "solve x^2 - 4 = 0 for x", detail: "Choose the solve variable explicitly.", sage: "solve(x^2 - 4 == 0, x)"),
            ]
        ),
        HelpSection(
            title: "Calculus",
            summary: "Derivatives, integrals, limits, series, sums, and products use compact calculator phrasing.",
            examples: [
                HelpExample(command: "integral x^2", detail: "Indefinite integral with inferred variable.", sage: "integrate(x^2, x)"),
                HelpExample(command: "integral x^2, x=0..1", detail: "Definite integral over a range.", sage: "integrate(x^2, (x, 0, 1))"),
                HelpExample(command: "integral x*y, wrt y", detail: "Explicit variable for an indefinite integral.", sage: "integrate(x*y, y)"),
                HelpExample(command: "double integral x*y, x=0..1, y=0..x", detail: "Typed-only double integral form.", sage: "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))"),
                HelpExample(command: "derivative sin(x^2)", detail: "Derivative, alias: diff.", sage: "derivative(sin(x^2), x)"),
                HelpExample(command: "derivative sin(x), 2", detail: "Second derivative.", sage: "derivative(sin(x), x, 2)"),
                HelpExample(command: "limit sin(x)/x, x->0", detail: "Two-sided limit.", sage: "limit(sin(x)/x, x=0)"),
                HelpExample(command: "limit 1/x, x->0, right", detail: "One-sided limit; left is also accepted.", sage: "limit(1/x, x=0, dir='+')"),
                HelpExample(command: "taylor sin(x), x=0, order=7", detail: "Taylor polynomial.", sage: "taylor(sin(x), x, 0, 7)"),
                HelpExample(command: "sum k^2, k=1..n", detail: "Symbolic summation.", sage: "sum(k^2, k, 1, n)"),
                HelpExample(command: "product 1 + 1/k, k=1..n", detail: "Symbolic product.", sage: "product(1 + 1/k, k, 1, n)"),
            ]
        ),
        HelpSection(
            title: "Plotting",
            summary: "Plot commands require explicit ranges so the generated Sage is predictable.",
            examples: [
                HelpExample(command: "plot sin(x), x=-pi..pi", detail: "2D plot over a required range.", sage: "plot(sin(x), (x, -pi, pi))"),
                HelpExample(command: "parametric_plot (cos(t), sin(t)), t=0..2*pi", detail: "Parametric plot; alias: parametric plot.", sage: "parametric_plot((cos(t), sin(t)), (t, 0, 2*pi))"),
                HelpExample(command: "implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2", detail: "Implicit plot; alias: implicit plot.", sage: "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))"),
            ]
        ),
        HelpSection(
            title: "Linear Algebra",
            summary: "Matrix commands accept Sage row lists, MATLAB-style row literals, variables, expressions, and tape references.",
            examples: [
                HelpExample(command: "matrix [1,2; 3,4]", detail: "Build a matrix.", sage: "matrix([[1,2],[3,4]])"),
                HelpExample(command: "vector [1,2,3]", detail: "Build a vector.", sage: "vector([1,2,3])"),
                HelpExample(command: "det [1,2; 3,4]", detail: "Determinant; alias: determinant.", sage: "matrix([[1,2],[3,4]]).det()"),
                HelpExample(command: "inverse M", detail: "Matrix inverse.", sage: "(M).inverse()"),
                HelpExample(command: "transpose M", detail: "Transpose.", sage: "(M).transpose()"),
                HelpExample(command: "rank M", detail: "Rank.", sage: "(M).rank()"),
                HelpExample(command: "rref M", detail: "Reduced row echelon form.", sage: "(M).rref()"),
                HelpExample(command: "eigenvalues M", detail: "Eigenvalues; alias: eigenvalue.", sage: "(M).eigenvalues()"),
                HelpExample(command: "eigenvectors M", detail: "Right eigenvectors; alias: eigenvector.", sage: "(M).eigenvectors_right()"),
            ]
        ),
        HelpSection(
            title: "Vector Calculus",
            summary: "Gradient, Hessian, and Jacobian commands keep vector notation compact.",
            examples: [
                HelpExample(command: "gradient x^2 + y^2", detail: "Gradient; alias: grad.", sage: "(x^2 + y^2).gradient()"),
                HelpExample(command: "gradient x^2*y + z, [x,y,z]", detail: "Gradient with explicit variables.", sage: "(x^2*y + z).gradient([x, y, z])"),
                HelpExample(command: "hessian x^2 + x*y + y^2", detail: "Hessian matrix.", sage: "(x^2 + x*y + y^2).hessian()"),
                HelpExample(command: "jacobian [x^2+y, sin(x*y)], [x,y]", detail: "Jacobian of functions with variables.", sage: "jacobian([x^2+y, sin(x*y)], [x, y])"),
            ]
        ),
        HelpSection(
            title: "Substitution And Numeric",
            summary: "Substitute values or request a numeric approximation from the input itself.",
            examples: [
                HelpExample(command: "subs x^2 + y, x=3, y=4", detail: "Substitute bindings; alias: substitute.", sage: "(x^2 + y).subs(x=3, y=4)"),
                HelpExample(command: "numeric pi", detail: "Numeric approximation; aliases: approx, decimal.", sage: "N(pi)"),
                HelpExample(command: "numeric sqrt(2), 50", detail: "Approximate with explicit digits.", sage: "N(sqrt(2), digits=50)"),
            ]
        ),
        HelpSection(
            title: "Symbols And Assumptions",
            summary: "Declare variables and assumptions without typing Sage boilerplate.",
            examples: [
                HelpExample(command: "var a b c", detail: "Declare symbolic variables.", sage: "var('a b c')"),
                HelpExample(command: "var a, b, c", detail: "Comma-separated declaration also works.", sage: "var('a b c')"),
                HelpExample(command: "assume x > 0", detail: "Comparison assumption.", sage: "assume(x > 0)"),
                HelpExample(command: "assume n is integer", detail: "Property assumption.", sage: "assume(n, 'integer')"),
                HelpExample(command: "assume x positive", detail: "Positive/negative comparison sugar.", sage: "assume(x > 0)"),
                HelpExample(command: "forget all", detail: "Clear assumptions.", sage: "forget()"),
            ]
        ),
        HelpSection(
            title: "Combinatorics And Number Theory",
            summary: "Common discrete-math helpers lower to the corresponding Sage functions.",
            examples: [
                HelpExample(command: "choose 10, 3", detail: "Binomial coefficient.", sage: "binomial(10, 3)"),
                HelpExample(command: "factorial 5", detail: "Factorial.", sage: "factorial(5)"),
                HelpExample(command: "gcd 12, 18", detail: "Greatest common divisor.", sage: "gcd(12, 18)"),
                HelpExample(command: "gcd 12, 18, 24", detail: "Three or more arguments collect into a list.", sage: "gcd([12, 18, 24])"),
                HelpExample(command: "lcm 4, 6", detail: "Least common multiple.", sage: "lcm(4, 6)"),
                HelpExample(command: "is_prime 104729", detail: "Primality test.", sage: "is_prime(104729)"),
                HelpExample(command: "factor_integer 3600", detail: "Integer factorization; alias: prime_factorization.", sage: "factor(3600)"),
            ]
        ),
        HelpSection(
            title: "Statistics",
            summary: "Distribution helpers lower to Casette's preloaded worker functions, which are also available to raw Sage input.",
            examples: [
                HelpExample(command: "mean [1, 2, 3]", detail: "Exact arithmetic mean.", sage: "sum([1, 2, 3])/len([1, 2, 3])"),
                HelpExample(command: "normal_pdf 0", detail: "Normal density.", sage: "normal_pdf(0)"),
                HelpExample(command: "normal_cdf z, mean=mu, sd=s", detail: "Normal CDF with optional parameters.", sage: "normal_cdf(z, mean=mu, sd=s)"),
                HelpExample(command: "normal_between -1, 1", detail: "Normal probability over an interval.", sage: "normal_between(-1, 1)"),
                HelpExample(command: "normal_inv .975", detail: "Normal inverse CDF.", sage: "normal_inv(.975)"),
                HelpExample(command: "binomial_pmf 3, n=10, p=.5", detail: "Binomial point probability.", sage: "binomial_pmf(3, n=10, p=.5)"),
                HelpExample(command: "binomial_cdf 3, n=10, p=.5", detail: "Binomial cumulative probability.", sage: "binomial_cdf(3, n=10, p=.5)"),
                HelpExample(command: "binomial_between 3, 7, n=10, p=.5", detail: "Binomial interval probability.", sage: "binomial_between(3, 7, n=10, p=.5)"),
                HelpExample(command: "binomial_at_most 3, n=10, p=.5", detail: "Binomial lower tail.", sage: "binomial_at_most(3, n=10, p=.5)"),
                HelpExample(command: "binomial_at_least 8, n=10, p=.5", detail: "Binomial upper tail.", sage: "binomial_at_least(8, n=10, p=.5)"),
                HelpExample(command: "poisson_pmf 2, lambda=3", detail: "Poisson point probability.", sage: "poisson_pmf(2, lambda_=3)"),
                HelpExample(command: "poisson_cdf 2, lambda=3", detail: "Poisson cumulative probability.", sage: "poisson_cdf(2, lambda_=3)"),
                HelpExample(command: "poisson_between 1, 4, lambda=3", detail: "Poisson interval probability.", sage: "poisson_between(1, 4, lambda_=3)"),
                HelpExample(command: "poisson_at_most 2, lambda=3", detail: "Poisson lower tail.", sage: "poisson_at_most(2, lambda_=3)"),
                HelpExample(command: "poisson_at_least 5, lambda=3", detail: "Poisson upper tail.", sage: "poisson_at_least(5, lambda_=3)"),
                HelpExample(command: "exponential_pdf 1, rate=2", detail: "Exponential density.", sage: "exponential_pdf(1, rate=2)"),
                HelpExample(command: "exponential_cdf 1, rate=2", detail: "Exponential cumulative probability.", sage: "exponential_cdf(1, rate=2)"),
                HelpExample(command: "exponential_between 1, 2, rate=2", detail: "Exponential interval probability.", sage: "exponential_between(1, 2, rate=2)"),
                HelpExample(command: "exponential_inv .95, rate=2", detail: "Exponential inverse CDF.", sage: "exponential_inv(.95, rate=2)"),
                HelpExample(command: "uniform_pdf .5, min=0, max=1", detail: "Uniform density.", sage: "uniform_pdf(.5, low=0, high=1)"),
                HelpExample(command: "uniform_cdf .5, min=0, max=1", detail: "Uniform cumulative probability.", sage: "uniform_cdf(.5, low=0, high=1)"),
                HelpExample(command: "uniform_between .2, .8, min=0, max=1", detail: "Uniform interval probability.", sage: "uniform_between(.2, .8, low=0, high=1)"),
                HelpExample(command: "uniform_inv .95, min=0, max=1", detail: "Uniform inverse CDF.", sage: "uniform_inv(.95, low=0, high=1)"),
            ]
        ),
        HelpSection(
            title: "Rules And Boundaries",
            summary: "These rules keep the mini-language small and predictable.",
            examples: [
                HelpExample(command: "factor x^4 - 1", detail: "Friendly: known command word followed by a space.", sage: "factor(x^4 - 1)"),
                HelpExample(command: "factor(x^4 - 1)", detail: "Raw Sage bypass: call syntax is untouched.", sage: "factor(x^4 - 1)"),
                HelpExample(command: "#14", detail: "Tape references can be reused inside friendly commands.", sage: "__casette_tape_refs[14]"),
                HelpExample(command: "plot sin(x)", detail: "Not accepted: plot requires a range.", sage: "Add a range, for example: plot sin(x), x=-pi..pi"),
            ]
        ),
    ]
}
