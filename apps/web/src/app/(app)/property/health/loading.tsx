export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-32 rounded-xl glass-light" />
      <div className="flex items-center gap-4 rounded-2xl glass-light p-5">
        <div className="h-20 w-20 rounded-full glass-standard shrink-0" />
        <div className="flex flex-col gap-2 flex-1">
          <div className="h-6 w-24 rounded-full glass-standard" />
          <div className="h-4 w-32 rounded-full glass-light" />
        </div>
      </div>
      <div className="grid grid-cols-3 gap-3">
        {[...Array(3)].map((_, i) => (
          <div key={i} className="h-24 rounded-2xl glass-light" />
        ))}
      </div>
      <div className="h-6 w-28 rounded-full glass-light" />
      {[...Array(3)].map((_, i) => (
        <div key={i} className="h-16 rounded-2xl glass-light" />
      ))}
    </div>
  )
}
