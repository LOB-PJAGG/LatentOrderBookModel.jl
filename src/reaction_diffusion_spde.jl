function initial_conditions_steady_state(rdpp::ReactionDiffusionPricePaths)
    φ = rdpp.source_term.λ / (2 * rdpp.source_term.μ * rdpp.D) .*
        [
            (rdpp.p₀ - xᵢ)*exp(rdpp.source_term.μ * (rdpp.p₀ - xᵢ)^2) -
            0.5 * sqrt(pi/rdpp.source_term.μ) *
            erf(sqrt(rdpp.source_term.μ) * (rdpp.p₀ - xᵢ))
            for xᵢ in rdpp.x
        ]
    return φ
end


function extract_mid_price(rdpp, lob_density)
    mid_price_ind = argmin(lob_density[lob_density .> 0])
    x1, y1 = rdpp.x[mid_price_ind], lob_density[mid_price_ind]
    x2, y2 = rdpp.x[mid_price_ind+1], lob_density[mid_price_ind+1]
    m = (y1-y2)/(x1-x2)
    c = y1-m*x1
    mid_price = round(-c/m, digits=2)
    return mid_price
end


function dtrw_solver(rdpp::ReactionDiffusionPricePaths)

    φ = ones(Float64, rdpp.M+1, rdpp.T)
    φ[:,1] = initial_conditions_steady_state(rdpp)
    Δx = (rdpp.x[end] - rdpp.x[1])/(rdpp.M)
    Δt = (Δx^2) / (2.0*rdpp.D)

    p =  ones(Float64, rdpp.T) * rdpp.p₀
    ϵ = rand(Normal(0.0,1.0), rdpp.T-1)
    P⁺s = ones(Float64, rdpp.M+1, rdpp.T-1)
    # Ps = ones(Float64, rdpp.M+1, rdpp.T-1)
    P⁻s = ones(Float64, rdpp.M+1, rdpp.T-1)
    # Simulate SPDE
    @inbounds for n = 1:rdpp.T-1
        Vₜ =  sign(ϵ[n]) * min(abs(rdpp.σ*ϵ[n]), Δx/Δt)
        V = (-Vₜ .* rdpp.x) ./ (2.0*rdpp.D)

        P⁺ = vcat(exp.(-rdpp.β.*V[2:end]), exp(-rdpp.β*V[end]))
        # P = exp.(-rdpp.β.*V[2:end-1])
        P⁻ = vcat(exp(-rdpp.β*V[1]) , exp.(-rdpp.β.*V[1:end-1]))
        Z = P⁺ .+ P⁻
        # Normalizing the probabilities
        P⁺ = P⁺ ./ Z
        # P = P ./ Z
        P⁻ = P⁻ ./ Z

        P⁺s[:,n] = P⁺
        # Ps[:,n-1] = P
        P⁻s[:,n] = P⁻

        φ₋₁ = φ[1,n] * (1-(Vₜ*Δx)/rdpp.D)
        φₘ₊₁ = φ[end,n] * (1+(Vₜ*Δx)/rdpp.D)

        P⁺₋₁ = P⁻[1]
        P⁻ₘ₊₁ = P⁺[end]

        φ[1,n+1] = P⁺₋₁ * φ₋₁ +
            P⁻[2] * φ[2,n] +
            exp(rdpp.nu*n*Δt) * rdpp.source_term(rdpp.x[1], p[n])

        φ[end,n+1] = P⁻ₘ₊₁ * φₘ₊₁ +
            P⁺[end-1] * φ[end-1,n] +
            exp(rdpp.nu*n*Δt) * rdpp.source_term(rdpp.x[end], p[n])


        # Compute Interior Points
        φ[2:end-1,n+1] = P⁺[1:end-2] .* φ[1:end-2,n] +
            P⁻[3:end] .* φ[3:end,n] +
            [exp(rdpp.nu*n*Δt) * rdpp.source_term(xᵢ, p[n])
            for xᵢ in rdpp.x[2:end-1]]

        φ[:,n+1] = exp(-rdpp.nu*n*Δt) .* φ[:,n+1]
        p[n+1] = extract_mid_price(rdpp, φ[:,n+1])
    end

    return φ, p, P⁺s ,P⁻s
end
