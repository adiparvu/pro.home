export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[88px] md:pb-6 animate-pulse">
      <div className="h-8 w-20 rounded-xl glass-light" />
      <div className="flex flex-col gap-2">
        {[...Array(10)].map((_, i) => (
          <div key={i} className="h-16 rounded-2xl glass-light" />
        ))}
      </div>
    </div>
  )
}
