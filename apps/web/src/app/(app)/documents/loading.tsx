export default function Loading() {
  return (
    <div className="flex flex-col gap-4 px-4 py-4 md:px-6 md:py-6 pb-[116px] md:pb-6 animate-pulse">
      <div className="h-8 w-36 rounded-xl glass-light" />
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        <div className="h-16 rounded-2xl glass-light" />
        <div className="h-16 rounded-2xl glass-light" />
        <div className="h-16 rounded-2xl glass-light" />
      </div>
      <div className="h-9 w-40 rounded-xl glass-light" />
      {[...Array(5)].map((_, i) => (
        <div key={i} className="h-20 rounded-2xl glass-light" />
      ))}
    </div>
  )
}
