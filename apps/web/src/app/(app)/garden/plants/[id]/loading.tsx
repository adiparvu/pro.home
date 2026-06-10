export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 animate-pulse">
      {/* Hero card */}
      <div className="rounded-2xl glass-light p-5">
        <div className="flex items-start gap-4">
          <div className="h-14 w-14 rounded-2xl glass-light" />
          <div className="flex-1 flex flex-col gap-2">
            <div className="h-5 w-24 rounded-full glass-light" />
            <div className="h-3.5 w-16 rounded-full glass-light" />
          </div>
        </div>
        <div className="mt-4 h-16 rounded-xl glass-light" />
      </div>
      {/* Details card */}
      <div className="rounded-2xl glass-light p-4 flex flex-col gap-3">
        <div className="h-3.5 w-16 rounded-full glass-light" />
        {[1, 2, 3].map((i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="h-8 w-8 rounded-lg glass-light" />
            <div className="flex flex-col gap-1 flex-1">
              <div className="h-3 w-12 rounded-full glass-light" />
              <div className="h-4 w-32 rounded-full glass-light" />
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
