module DotNET

import Pkg.Artifacts:@artifact_str

export CLRObject,null,isnull,CLRException,@T_str,
    clrtypeof,isclrtype,isassignable,
    clreltype,
    delegate

include("typedef.jl")

include("CoreCLR.jl")
using .CoreCLR

include("CLRBridge.jl")
using .CLRBridge

include("typeinfo.jl")

include("marshalling.jl")

include("callback.jl")

include("reflection.jl")

include("operators.jl")

struct DummyCLRHost <: CLRHost end

const CURRENT_CLR_HOST = Ref{CLRHost}(DummyCLRHost())

function __init__()
    if CURRENT_CLR_HOST[] != DummyCLRHost() return end
    coreclr = detect_runtime(CoreCLRHost)
    if !isempty(coreclr)
        inittask = @task begin
            init_coreclr(first(coreclr))
        end
        schedule(inittask)
        wait(inittask)
        return
    end
    @error """
    No .NET Core runtime found on this system.
    Try specifying DOTNET_ROOT environment variable or adding 'dotnet' executable to PATH, then run 'DotNET.__init__()' again.
    Note that .NET Framework is current not supported.
    """
end

function init_coreclr(runtime)
    CoreCLR.init(runtime)
    dir = artifact"clrbridge"
    clrbridge = joinpath(dir, "CLRBridge.dll")
    if !isfile(clrbridge)
        error("""
        Artifact is present but CLRBridge.dll not found, possibly due to a broken package installation.
        You may need to delete the artifact directory '$dir' and try 'DotNET.__init__()' again.
        """)
    end
    tpalist = build_tpalist(dirname(runtime.path))
    push!(tpalist, clrbridge)
    CURRENT_CLR_HOST[] = create_host(CoreCLRHost;tpalist = tpalist)
    CLRBridge.init(CURRENT_CLR_HOST[])
    add_typeresolver()
end

function build_tpalist(dir)
    joinpath.(dir, filter(x->splitext(x)[2] == ".dll", readdir(dir)))
end

function add_typeresolver()
    d = delegate(T"System.ResolveEventHandler") do sender, args
        name = args.Name
        for asm in T"System.AppDomain, mscorlib".CurrentDomain.GetAssemblies()
            ty = asm.GetType(name)
            if !isnull(ty)
                return asm
            end
        end
        return CLRObject(0)
    end
    evt = getevent(T"System.AppDomain, mscorlib", :TypeResolve)
    if !isnull(evt)
        evt.AddEventHandler(T"System.AppDomain, mscorlib".CurrentDomain, d)
    end
end

end # module
