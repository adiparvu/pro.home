export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6 animate-pulse">
      <div className="h-8 w-36 rounded-xl glass-light" />
      <div className="h-32 rounded-2xl glass-light" />
      <div className="h-6 w-28 rounded-full glass-light" />
      <div className="grid grid-cols-2 gap-3">
        {[...Array(6)].map((_, i) => (
          <div key={i} className="h-14 rounded-xl glass-light" />
        ))}
      </div>
      <div className="h-6 w-24 rounded-full glass-light" />
      <div className="h-20 rounded-2xl glass-light" />
    </div>
  )
}
