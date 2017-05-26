module FASTQDemultiplexerKallisto

import FASTQDemultiplexer:
    Output, Interpreter, InterpretedRecord,
    mergeoutput
using DataFrames
using Cxx
using Weave

const path_to_lib=Pkg.dir("FASTQDemultiplexerKallisto","deps")
addHeaderDir(path_to_lib, kind=C_System)
Libdl.dlopen(joinpath(path_to_lib, "libkallisto_align.so"), Libdl.RTLD_GLOBAL)
cxxinclude(joinpath(path_to_lib,"align-lib.h"))

type OutputKallisto <: Output
    results::DataFrame
    writealignment::Bool
    writereport::Bool
end

function OutputKallisto(protocol::Interpreter;
                        index::String = "",
                        writealignment = true,
                        writerport = true,
                        kwargs...)
    if !isfile(index)
        error("Could not locate index file $index")
    else
        @cxx loadIndex(pointer(index))
    end

    results = DataFrame(cellid = UInt[],
                        umiid = UInt[],
                        groupname = PooledDataArray(String,UInt8,0),
                        alignment = Int[])
    return OutputKallisto(results,
                          writealignment,
                          writereport)
end

function align(ir::InterpretedRecord)
    insert = pointer(ir.output.data)+first(ir.output.sequence)
    return @cxx alignRead(insert,length(ir.output.sequence))
end

function Base.write(o::OutputKallisto,
                    ir::InterpretedRecord)
    if ir.groupid >= 0
        alignment = align(ir)
        push!(o.results,(ir.cellid,ir.umiid,ir.groupname,alignment))
    end
end

function mergeoutput(outputs::Vector{OutputKallisto};
                     outputdir::String=".",
                     kwargs...)
    if length(output) > 1
        results = vcat((o.results for o in outputs)...)
    else
        results = outputs[1].results
    end

    if outputs[1].writealignment
        writetable(joinpath(outputdir,"alignment.tsv"),results)
    end

    if outputs[1].writereport
        report(results, outputdir)
    end
end

function report(results, outputdir)
    args = Dict{String,Any}()
    args["results"] = results

    weave(Pkg.dir("FASTQDemultiplexerKallisto",
                  "src","weave","alignment.jmd"),
          args = args,
          out_path = outputdir)
end

end
